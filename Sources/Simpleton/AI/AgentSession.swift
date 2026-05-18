// Sources/Simpleton/AI/AgentSession.swift
import Foundation
import AppKit
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
    @Published private(set) var stepNumber: Int = 0

    var onMessage: ((ChatMessage) -> Void)?
    /// (cmd, explanation, paneLabel, handler(action, overridePaneID?))
    var onApprovalNeeded: ((String, String, String, @escaping (ApprovalAction, PaneID?) -> Void) -> Void)?
    /// (cmd, output, paneLabel)
    var onCommandExecuted: ((String, String, String) -> Void)?
    var onComplete: (() -> Void)?
    var onError: ((String) -> Void)?

    private let aiService: AIService
    private let processRunner = ProcessRunner()
    private let promptBuilder = PromptBuilder()
    private let toolRegistry: ToolHandlerRegistry
    private var isCancelled = false
    private var pendingApprovalContinuation: CheckedContinuation<(ApprovalAction, PaneID?), Never>?
    private var turnCount = 0
    var maxTurns = 25
    private var warningTurn: Int { max(maxTurns - 10, 10) }

    init(aiService: AIService) {
        self.aiService = aiService
        self.toolRegistry = ToolHandlerRegistry([
            FileTools(), TerminalTools(), GitTools(),
            SystemTools(), NetworkTools(), ProcessTools(),
        ])
    }

    func cancel() {
        isCancelled = true
        pendingApprovalContinuation?.resume(returning: (.stop, nil))
        pendingApprovalContinuation = nil
        aiService.cancelAll()
        state = .idle
    }

    // MARK: - Chat with Tools (free-text conversation that can execute commands)

    func chat(
        message: String,
        history: [ConversationTurn],
        systemPrompt: String,
        conversation: TabConversation,
        focusedPane: PaneController,
        autopilot: Bool
    ) async {
        isCancelled = false
        turnCount = 0
        stepNumber = 0
        var turns = history
        turns.append(.user(message))

        while !isCancelled {
            turnCount += 1
            if turnCount > maxTurns {
                onMessage?(ChatMessage(role: "assistant", content: "Reached the maximum number of steps (\(maxTurns)). Stopping to avoid runaway execution. Here's what was accomplished so far."))
                state = .done
                onComplete?()
                return
            }

            // Inject soft warning near the limit
            var turnOptions = AIOptions(maxTokens: 4000, temperature: 0.3)
            var effectiveSystem = systemPrompt
            if turnCount == warningTurn {
                effectiveSystem += "\n\n[SYSTEM NOTE: You are approaching the step limit (\(maxTurns)). Start wrapping up — finish the current task and provide a summary.]"
            }

            state = .streaming
            do {
                let result = try await aiService.agentTurn(system: effectiveSystem, turns: turns, options: turnOptions)
                switch result {
                case .text(let text):
                    onMessage?(ChatMessage(role: "assistant", content: text))
                    state = .done
                    onComplete?()
                    return

                case .toolCall(let id, let name, let args):
                    if name == "run_command" { stepNumber += 1 }
                    let result = await handleToolCall(
                        id: id, name: name, args: args,
                        conversation: conversation, focusedPane: focusedPane,
                        autopilot: autopilot, turns: &turns
                    )
                    if result == .stopped { return }
                }
            } catch {
                state = .error(error.localizedDescription)
                onError?(error.localizedDescription)
                return
            }
        }
    }

    private enum ToolHandleResult { case continued, stopped }

    /// Dispatch a tool call to the appropriate handler.
    private func handleToolCall(
        id: String, name: String, args: [String: Any],
        conversation: TabConversation, focusedPane: PaneController,
        autopilot: Bool, turns: inout [ConversationTurn]
    ) async -> ToolHandleResult {
        if name == "run_command" {
            return await handleRunCommand(
                id: id, args: args, conversation: conversation,
                focusedPane: focusedPane, autopilot: autopilot, turns: &turns
            )
        }

        let context = ToolContext(conversation: conversation, focusedPane: focusedPane, processRunner: processRunner)
        if let handler = toolRegistry.handler(for: name) {
            let output = await handler.handle(name: name, args: args, context: context)
            turns.append(.toolResult(toolCallID: id, output: output))
            return .continued
        }

        turns.append(.toolResult(toolCallID: id, output: "Unknown tool: \(name)"))
        return .continued
    }

    /// Handle run_command tool call with approval flow.
    private func handleRunCommand(
        id: String, args: [String: Any],
        conversation: TabConversation, focusedPane: PaneController,
        autopilot: Bool, turns: inout [ConversationTurn]
    ) async -> ToolHandleResult {
        guard let cmd = args["cmd"] as? String else {
            turns.append(.toolResult(toolCallID: id, output: "Missing 'cmd' parameter"))
            return .continued
        }
        let explanation = args["explanation"] as? String ?? ""
        let paneNumber = args["pane"] as? Int
        let resolved = conversation.resolvePane(number: paneNumber)
        let targetPane = resolved?.pane ?? focusedPane
        let targetLabel = resolved?.label ?? "focused pane"

        if autopilot {
            await executeCommand(cmd, toolCallID: id, explanation: explanation, pane: targetPane, paneLabel: targetLabel, wasFallback: resolved?.wasFallback ?? false, turns: &turns)
            return .continued
        }

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
            return .continued
        case .skip:
            turns.append(.toolResult(toolCallID: id, output: "[Command skipped by user]"))
            return .continued
        case .stop:
            state = .done
            onComplete?()
            return .stopped
        }
    }

    // MARK: - Skill Execution (Multi-Pane)

    func run(skill: Skill, params: [String: String], conversation: TabConversation, focusedPane: PaneController, autopilot: Bool) async {
        isCancelled = false
        let system = promptBuilder.buildSystemPrompt(skill: skill, params: params, conversation: conversation, focusedPane: focusedPane)
        let initialMessage = "Run the \(skill.name) skill.\(promptBuilder.buildParamSummary(params: params))"
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

                case .toolCall(let id, let name, let args):
                    let result = await handleToolCall(
                        id: id, name: name, args: args,
                        conversation: conversation, focusedPane: focusedPane,
                        autopilot: autopilot, turns: &turns
                    )
                    if result == .stopped { return }
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
        let system = promptBuilder.buildSystemPromptLegacy(skill: skill, params: params, pane: pane)
        let initialMessage = "Run the \(skill.name) skill.\(promptBuilder.buildParamSummary(params: params))"
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
                case .toolCall(let id, let name, let args):
                    // Legacy path: only handle run_command, ignore other tools
                    guard name == "run_command", let cmd = args["cmd"] as? String else {
                        turns.append(.toolResult(toolCallID: id, output: "Tool \(name) not available in legacy mode"))
                        continue
                    }
                    let explanation = args["explanation"] as? String ?? ""
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
        let uuid = UUID().uuidString.prefix(8)
        let sentinel = "__SIMPLETON_DONE_\(uuid)__"
        // Embed exit code in sentinel: __SIMPLETON_DONE_xxxx_EXIT_0__
        let fullCommand = "\(cmd)\n__simpleton_ec=$?; printf '\\n\(sentinel)_EXIT_%d__\\n' \"$__simpleton_ec\"; exit_unused=$__simpleton_ec\n"
        pane.terminalView.send(data: Array(fullCommand.utf8)[...])

        state = .capturingOutput
        let (output, exitCode) = await captureOutputWithExitCode(sentinel: sentinel, pane: pane)

        var result = ""
        if wasFallback {
            result += "[Note: Target pane was closed. Command ran on \(paneLabel) instead.]\n"
        }
        if let code = exitCode {
            result += "[exit code: \(code)]\n"
        }
        result += output
        onCommandExecuted?(cmd, result, paneLabel)
        turns.append(.toolResult(toolCallID: toolCallID, output: result))
    }

    private func captureOutputWithExitCode(sentinel: String, pane: PaneController) async -> (output: String, exitCode: Int?) {
        let terminal = pane.terminalView.getTerminal()
        let maxWait = 30_000
        let pollMs  = 200
        var elapsed = 0
        // Pattern: __SIMPLETON_DONE_xxxx_EXIT_N__
        let exitPattern = "\(sentinel)_EXIT_"

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

            if let range = buffer.range(of: exitPattern) {
                let before = String(buffer[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                // Extract exit code number after _EXIT_
                let afterPrefix = String(buffer[range.upperBound...])
                let exitCode: Int?
                if let endRange = afterPrefix.range(of: "__") {
                    exitCode = Int(afterPrefix[..<endRange.lowerBound])
                } else {
                    exitCode = nil
                }
                return (before, exitCode)
            }

            // Fallback: check for sentinel without exit code (old format)
            if buffer.contains(sentinel) {
                if let range = buffer.range(of: sentinel) {
                    let before = String(buffer[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    return (before, nil)
                }
            }
        }
        return ("[Timed out waiting for command output after \(maxWait/1000)s]", nil)
    }

}
