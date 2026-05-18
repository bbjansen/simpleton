// Sources/Simpleton/AI/AgentSession.swift
import Foundation
import SimpletonCore

@MainActor
final class AgentSession: ObservableObject {

    enum State: Equatable {
        case idle
        case streaming
        case waitingApproval(cmd: String, explanation: String, toolCallID: String)
        case executing(cmd: String)
        case capturingOutput
        case done
        case error(String)
    }

    enum ApprovalAction { case allow, skip, stop }

    @Published private(set) var state: State = .idle

    var onMessage: ((ChatMessage) -> Void)?
    var onApprovalNeeded: ((String, String, @escaping (ApprovalAction) -> Void) -> Void)?
    var onCommandExecuted: ((String, String) -> Void)?
    var onComplete: (() -> Void)?
    var onError: ((String) -> Void)?

    private let aiService: AIService
    private var isCancelled = false
    private var pendingApprovalContinuation: CheckedContinuation<ApprovalAction, Never>?

    init(aiService: AIService) {
        self.aiService = aiService
    }

    func cancel() {
        isCancelled = true
        pendingApprovalContinuation?.resume(returning: .stop)
        pendingApprovalContinuation = nil
        aiService.cancelAll()
        state = .idle
    }

    func run(skill: Skill, params: [String: String], pane: PaneController, autopilot: Bool) async {
        isCancelled = false
        let system = buildSystemPrompt(skill: skill, params: params, pane: pane)
        let initialMessage = "Run the \(skill.name) skill.\(buildParamSummary(params: params))"
        var turns: [ConversationTurn] = [.user(initialMessage)]

        while !isCancelled {
            state = .streaming
            do {
                let result = try await aiService.agentTurn(system: system, turns: turns)
                switch result {
                case .text(let text):
                    onMessage?(ChatMessage(role: "assistant", content: text))
                    state = .done
                    onComplete?()
                    return

                case .toolCall(let id, let cmd, let explanation):
                    if autopilot {
                        await executeCommand(cmd, toolCallID: id, explanation: explanation, pane: pane, turns: &turns)
                    } else {
                        state = .waitingApproval(cmd: cmd, explanation: explanation, toolCallID: id)
                        let action = await withCheckedContinuation { (continuation: CheckedContinuation<ApprovalAction, Never>) in
                            pendingApprovalContinuation = continuation
                            onApprovalNeeded?(cmd, explanation) { [weak self] action in
                                self?.pendingApprovalContinuation?.resume(returning: action)
                                self?.pendingApprovalContinuation = nil
                            }
                        }
                        switch action {
                        case .allow:
                            await executeCommand(cmd, toolCallID: id, explanation: explanation, pane: pane, turns: &turns)
                        case .skip:
                            turns.append(.toolResult(toolCallID: id, output: "[Command skipped by user]"))
                        case .stop:
                            state = .done
                            onComplete?()
                            return
                        }
                    }
                }
            } catch {
                state = .error(error.localizedDescription)
                onError?(error.localizedDescription)
                return
            }
        }
    }

    private func executeCommand(
        _ cmd: String, toolCallID: String, explanation: String,
        pane: PaneController, turns: inout [ConversationTurn]
    ) async {
        state = .executing(cmd: cmd)
        let sentinel = "__SIMPLETON_DONE_\(UUID().uuidString.prefix(8))__"
        let fullCommand = "\(cmd)\nprintf '\(sentinel)\\n'\n"
        pane.terminalView.send(data: Array(fullCommand.utf8)[...])

        state = .capturingOutput
        let output = await captureOutput(sentinel: sentinel, pane: pane)
        onCommandExecuted?(cmd, output)
        turns.append(.toolResult(toolCallID: toolCallID, output: output))
    }

    private func captureOutput(sentinel: String, pane: PaneController) async -> String {
        let terminal = pane.terminalView.getTerminal()
        let maxWait = 30_000
        let pollMs  = 200
        var elapsed = 0

        while elapsed < maxWait && !isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(pollMs) * 1_000_000)
            elapsed += pollMs

            let rows = terminal.rows
            var lines: [String] = []
            for row in 0..<rows {
                if let line = terminal.getLine(row: row) {
                    lines.append(line.translateToString(trimRight: true))
                }
            }
            let buffer = lines.joined(separator: "\n")

            if buffer.contains(sentinel) {
                if let range = buffer.range(of: sentinel) {
                    let before = String(buffer[..<range.lowerBound])
                    return before.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return "[Timed out waiting for command output]"
    }

    private func buildSystemPrompt(skill: Skill, params: [String: String], pane: PaneController) -> String {
        var prompt = skill.systemPrompt
        for (key, value) in params {
            prompt = prompt.replacingOccurrences(of: "{\(key)}", with: value)
        }
        let ctx = AIContextBuilder.build(terminalView: pane.terminalView, cwd: pane.currentDirectory, shell: nil, includeSelection: false)
        let ctxStr = AIContextBuilder.formatForPrompt(ctx)
        return """
        You are an autonomous terminal agent. Complete the following task step by step using run_command.
        When the task is fully done, respond with a plain text summary (no tool call).

        TASK: \(prompt)

        CONTEXT:
        \(ctxStr)
        """
    }

    private func buildParamSummary(params: [String: String]) -> String {
        guard !params.isEmpty else { return "" }
        let list = params.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        return " Parameters: \(list)."
    }
}
