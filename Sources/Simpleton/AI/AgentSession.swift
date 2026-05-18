// Sources/Simpleton/AI/AgentSession.swift
import Foundation
import SimpletonCore

@MainActor
final class AgentSession: ObservableObject {

    enum State: Equatable {
        case idle
        case streaming
        case waitingApproval(cmd: String, explanation: String, toolCallID: String, paneLabel: String)
        case executing(cmd: String)
        case capturingOutput
        case done
        case error(String)
    }

    enum ApprovalAction { case allow, skip, stop }

    @Published private(set) var state: State = .idle

    var onMessage: ((ChatMessage) -> Void)?
    /// (cmd, explanation, paneLabel, handler(action, overridePaneID?))
    var onApprovalNeeded: ((String, String, String, @escaping (ApprovalAction, PaneID?) -> Void) -> Void)?
    /// (cmd, output, paneLabel)
    var onCommandExecuted: ((String, String, String) -> Void)?
    var onComplete: (() -> Void)?
    var onError: ((String) -> Void)?

    private let aiService: AIService
    private var isCancelled = false
    private var pendingApprovalContinuation: CheckedContinuation<(ApprovalAction, PaneID?), Never>?

    init(aiService: AIService) {
        self.aiService = aiService
    }

    func cancel() {
        isCancelled = true
        pendingApprovalContinuation?.resume(returning: (.stop, nil))
        pendingApprovalContinuation = nil
        aiService.cancelAll()
        state = .idle
    }

    // MARK: - Multi-Pane Entry Point

    func run(skill: Skill, params: [String: String], conversation: TabConversation, focusedPane: PaneController, autopilot: Bool) async {
        isCancelled = false
        let system = buildSystemPrompt(skill: skill, params: params, conversation: conversation, focusedPane: focusedPane)
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
                    let paneNumber = extractPaneNumber(from: explanation)
                    let resolved = conversation.resolvePane(number: paneNumber)
                    let targetPane = resolved?.pane ?? focusedPane
                    let targetLabel = resolved?.label ?? "focused pane"

                    if autopilot {
                        await executeCommand(cmd, toolCallID: id, explanation: explanation, pane: targetPane, paneLabel: targetLabel, wasFallback: resolved?.wasFallback ?? false, turns: &turns)
                    } else {
                        state = .waitingApproval(cmd: cmd, explanation: explanation, toolCallID: id, paneLabel: targetLabel)
                        let (action, overridePaneID) = await withCheckedContinuation { (continuation: CheckedContinuation<(ApprovalAction, PaneID?), Never>) in
                            pendingApprovalContinuation = continuation
                            onApprovalNeeded?(cmd, explanation, targetLabel) { [weak self] action, overrideID in
                                self?.pendingApprovalContinuation?.resume(returning: (action, overrideID))
                                self?.pendingApprovalContinuation = nil
                            }
                        }
                        switch action {
                        case .allow:
                            let finalPane: PaneController
                            let finalLabel: String
                            if let overrideID = overridePaneID,
                               let idx = conversation.paneOrder.firstIndex(of: overrideID),
                               let overrideResolved = conversation.resolvePane(number: idx + 1) {
                                finalPane = overrideResolved.pane
                                finalLabel = overrideResolved.label
                            } else {
                                finalPane = targetPane
                                finalLabel = targetLabel
                            }
                            await executeCommand(cmd, toolCallID: id, explanation: explanation, pane: finalPane, paneLabel: finalLabel, wasFallback: false, turns: &turns)
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

    // MARK: - Legacy Single-Pane Entry Point

    func run(skill: Skill, params: [String: String], pane: PaneController, autopilot: Bool) async {
        isCancelled = false
        let system = buildSystemPromptLegacy(skill: skill, params: params, pane: pane)
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
                        await executeCommand(cmd, toolCallID: id, explanation: explanation, pane: pane, paneLabel: "focused pane", wasFallback: false, turns: &turns)
                    } else {
                        state = .waitingApproval(cmd: cmd, explanation: explanation, toolCallID: id, paneLabel: "focused pane")
                        let (action, _) = await withCheckedContinuation { (continuation: CheckedContinuation<(ApprovalAction, PaneID?), Never>) in
                            pendingApprovalContinuation = continuation
                            onApprovalNeeded?(cmd, explanation, "focused pane") { [weak self] action, _ in
                                self?.pendingApprovalContinuation?.resume(returning: (action, nil))
                                self?.pendingApprovalContinuation = nil
                            }
                        }
                        switch action {
                        case .allow:
                            await executeCommand(cmd, toolCallID: id, explanation: explanation, pane: pane, paneLabel: "focused pane", wasFallback: false, turns: &turns)
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

    // MARK: - Command Execution

    private func executeCommand(
        _ cmd: String, toolCallID: String, explanation: String,
        pane: PaneController, paneLabel: String, wasFallback: Bool,
        turns: inout [ConversationTurn]
    ) async {
        state = .executing(cmd: cmd)
        let sentinel = "__SIMPLETON_DONE_\(UUID().uuidString.prefix(8))__"
        let fullCommand = "\(cmd)\nprintf '\(sentinel)\\n'\n"
        pane.terminalView.send(data: Array(fullCommand.utf8)[...])

        state = .capturingOutput
        let output = await captureOutput(sentinel: sentinel, pane: pane)
        var result = output
        if wasFallback {
            result = "[Note: Target pane was closed. Command ran on \(paneLabel) instead.]\n" + output
        }
        onCommandExecuted?(cmd, result, paneLabel)
        turns.append(.toolResult(toolCallID: toolCallID, output: result))
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

    // MARK: - System Prompts

    private func buildSystemPrompt(skill: Skill, params: [String: String], conversation: TabConversation, focusedPane: PaneController) -> String {
        var prompt = skill.systemPrompt
        for (key, value) in params {
            prompt = prompt.replacingOccurrences(of: "{\(key)}", with: value)
        }

        let ctxStr: String
        if let composite = conversation.buildCompositeContext() {
            ctxStr = AIContextBuilder.formatCompositeForPrompt(composite)
        } else {
            let ctx = AIContextBuilder.build(terminalView: focusedPane.terminalView, cwd: focusedPane.currentDirectory, shell: nil, includeSelection: false)
            ctxStr = AIContextBuilder.formatForPrompt(ctx)
        }

        return """
        You are an autonomous terminal agent. Complete the following task step by step using run_command.
        When the task is fully done, respond with a plain text summary (no tool call).

        TASK: \(prompt)

        CONTEXT:
        \(ctxStr)
        """
    }

    private func buildSystemPromptLegacy(skill: Skill, params: [String: String], pane: PaneController) -> String {
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

    /// Extract pane number from tool call explanation.
    private func extractPaneNumber(from explanation: String) -> Int? {
        let pattern = "(?i)pane\\s*:?\\s*(\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: explanation, range: NSRange(location: 0, length: (explanation as NSString).length)),
              match.numberOfRanges >= 2 else { return nil }
        let numStr = (explanation as NSString).substring(with: match.range(at: 1))
        return Int(numStr)
    }
}
