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
    }

    /// Poll terminal buffer for sentinel indicating command completion.
    func captureOutputWithExitCode(sentinel: String, pane: PaneController) async -> (output: String, exitCode: Int?) {
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
