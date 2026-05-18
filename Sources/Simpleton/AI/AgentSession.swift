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
        var turns = history
        turns.append(.user(message))

        while !isCancelled {
            state = .streaming
            do {
                let result = try await aiService.agentTurn(system: systemPrompt, turns: turns, options: AIOptions(maxTokens: 4000, temperature: 0.3))
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

    private enum ToolHandleResult { case continued, stopped }

    /// Dispatch a tool call to the appropriate handler.
    private func handleToolCall(
        id: String, name: String, args: [String: Any],
        conversation: TabConversation, focusedPane: PaneController,
        autopilot: Bool, turns: inout [ConversationTurn]
    ) async -> ToolHandleResult {
        switch name {
        case "run_command":
            return await handleRunCommand(
                id: id, args: args, conversation: conversation,
                focusedPane: focusedPane, autopilot: autopilot, turns: &turns
            )
        case "read_pane_output":
            let paneNum = args["pane"] as? Int
            let lines = min(args["lines"] as? Int ?? 50, 200)
            let resolved = conversation.resolvePane(number: paneNum)
            let pane = resolved?.pane ?? focusedPane
            let label = resolved?.label ?? "focused pane"

            let output = readTerminalOutput(pane: pane, lines: lines)
            turns.append(.toolResult(toolCallID: id, output: "[\(label)] Recent output (\(lines) lines):\n\(output)"))
            return .continued

        case "list_panes":
            let output = listPanesOutput(conversation: conversation, focusedPane: focusedPane)
            turns.append(.toolResult(toolCallID: id, output: output))
            return .continued

        case "get_pane_state":
            let paneNum = args["pane"] as? Int ?? 1
            let resolved = conversation.resolvePane(number: paneNum)
            if let pane = resolved?.pane {
                let output = paneStateOutput(pane: pane, label: resolved?.label ?? "Pane \(paneNum)")
                turns.append(.toolResult(toolCallID: id, output: output))
            } else {
                turns.append(.toolResult(toolCallID: id, output: "Pane \(paneNum) not found."))
            }
            return .continued

        default:
            turns.append(.toolResult(toolCallID: id, output: "Unknown tool: \(name)"))
            return .continued
        }
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

    // MARK: - Read-Only Tool Implementations

    private func readTerminalOutput(pane: PaneController, lines: Int) -> String {
        let terminal = pane.terminalView.getTerminal()
        let totalRows = terminal.rows
        let startRow = max(0, totalRows - lines)
        var outputLines: [String] = []
        for row in startRow..<totalRows {
            if let line = terminal.getLine(row: row) {
                let text = line.translateToString(trimRight: true)
                if !text.isEmpty { outputLines.append(text) }
            }
        }
        let output = outputLines.joined(separator: "\n")
        return output.isEmpty ? "[No output]" : output
    }

    private func listPanesOutput(conversation: TabConversation, focusedPane: PaneController) -> String {
        guard let context = conversation.buildCompositeContext() else {
            return "Panes: 1 (focused)\nCWD: \(focusedPane.currentDirectory ?? "unknown")"
        }
        var lines: [String] = ["Panes in this tab:\n"]
        for pane in context.panes {
            let focus = pane.isFocused ? " (focused)" : ""
            let cwdStr = pane.cwd ?? "unknown"
            let shellStr = pane.shell ?? "shell"
            let connStr: String
            switch pane.connectionType {
            case .local: connStr = "local"
            case .ssh: connStr = "SSH"
            }
            lines.append("  \(pane.label)\(focus) — \(cwdStr) [\(shellStr), \(connStr)]")
        }
        return lines.joined(separator: "\n")
    }

    private func paneStateOutput(pane: PaneController, label: String) -> String {
        let cwd = pane.currentDirectory ?? "unknown"
        let connStr: String
        let shellStr: String
        switch pane.connectionType {
        case .local(let shell, _):
            connStr = "local"
            shellStr = URL(fileURLWithPath: shell).lastPathComponent
        case .ssh:
            connStr = "SSH (\(pane.sshHost ?? "unknown"))"
            shellStr = "remote"
        }
        let stateStr: String
        switch pane.state {
        case .running: stateStr = "running"
        case .exited(let code): stateStr = "exited (code \(code))"
        case .disconnected: stateStr = "disconnected"
        case .connecting: stateStr = "connecting"
        case .authRequired: stateStr = "auth required"
        }
        let output = readTerminalOutput(pane: pane, lines: 30)
        return """
        \(label)
        CWD: \(cwd)
        Shell: \(shellStr)
        Connection: \(connStr)
        State: \(stateStr)
        Recent output:
        \(output)
        """
    }

    // MARK: - Skill Execution (Multi-Pane)

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
