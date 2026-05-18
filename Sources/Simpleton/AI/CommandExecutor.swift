// Sources/Simpleton/AI/CommandExecutor.swift
import Foundation
import SimpletonCore

/// Command execution and approval flow — extracted from AgentSession for clarity.
extension AgentSession {

    enum ToolHandleResult { case continued, stopped }

    /// Handle run_command tool call with approval flow.
    func handleRunCommand(
        id: String, args: [String: Any],
        conversation: TabConversation, focusedPane: PaneController,
        autopilotMode: AutopilotMode, turns: inout [ConversationTurn]
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

        let shouldAutoApprove: Bool
        switch autopilotMode {
        case .full:
            shouldAutoApprove = true
        case .safe:
            shouldAutoApprove = CommandClassifier.isSafe(cmd)
        case .off:
            shouldAutoApprove = false
        }

        if shouldAutoApprove {
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

    /// Execute a command in a pane, injecting a sentinel for output capture.
    func executeCommand(
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

        // Publish to workspace event bus for cross-tab awareness
        if let bus = eventBus, let tabID = pane.eventBusTabID {
            let snippet = String(output.prefix(200))
            bus.publish(WorkspaceEvent(
                id: UUID(),
                timestamp: Date(),
                tabID: tabID,
                paneLabel: pane.paneLabel ?? paneLabel,
                type: .commandCompleted(cmd: cmd, exitCode: Int32(exitCode ?? 0), outputSnippet: snippet)
            ))
        }
    }

    /// Poll terminal buffer for sentinel indicating command completion.
    func captureOutputWithExitCode(sentinel: String, pane: PaneController) async -> (output: String, exitCode: Int?) {
        let terminal = pane.terminalView.getTerminal()
        let maxWait = 30_000
        let pollMs  = 200
        var elapsed = 0
        var lastBufferHash: Int = 0
        var stableElapsed = 0
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

            // Stall detection: check if buffer has changed
            let currentHash = buffer.hashValue
            if currentHash == lastBufferHash {
                stableElapsed += pollMs
            } else {
                stableElapsed = 0
                lastBufferHash = currentHash
            }

            // After 5 seconds with no output change, check for interactive prompt
            if stableElapsed >= 5000 {
                let lastLine = lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                let looksLikePrompt = lastLine.hasSuffix(":") || lastLine.hasSuffix("?") ||
                    lastLine.hasSuffix(">") || lastLine.hasSuffix("]") ||
                    lastLine.lowercased().contains("password") ||
                    lastLine.contains("[y/") || lastLine.contains("[Y/") ||
                    lastLine.contains("(y/n)") || lastLine.contains("(Y/N)")
                if looksLikePrompt {
                    let output = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        .joined(separator: "\n")
                    return ("[Command appears to be waiting for input. Last line: '\(lastLine)'. Use read_pane_output to check and send_keys to respond.]" +
                            "\n\nOutput so far:\n\(output)", nil)
                }
                stableElapsed = 0
            }
        }
        return ("[Timed out waiting for command output after \(maxWait/1000)s]", nil)
    }
}
