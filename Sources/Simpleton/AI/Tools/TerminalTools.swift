// Sources/Simpleton/AI/Tools/TerminalTools.swift
import Foundation
import SwiftTerm
import SimpletonCore

@MainActor
struct TerminalTools: ToolHandler {
    static let handledTools: Set<String> = [
        "read_pane_output", "list_panes", "get_pane_state", "send_keys",
    ]

    func handle(name: String, args: [String: Any], context: ToolContext) async -> String {
        switch name {
        case "read_pane_output":
            return handleReadPaneOutput(args, context: context)
        case "list_panes":
            return handleListPanes(context: context)
        case "get_pane_state":
            return handleGetPaneState(args, context: context)
        case "send_keys":
            return handleSendKeys(args, context: context)
        default:
            return "Unknown terminal tool: \(name)"
        }
    }

    // MARK: - Tool Implementations

    private func handleReadPaneOutput(_ args: [String: Any], context: ToolContext) -> String {
        let paneNum = args["pane"] as? Int
        let lines = min(args["lines"] as? Int ?? 50, 200)
        let resolved = context.conversation.resolvePane(number: paneNum)
        let pane = resolved?.pane ?? context.focusedPane
        let label = resolved?.label ?? "focused pane"

        let output = readTerminalOutput(pane: pane, lines: lines)
        return "[\(label)] Recent output (\(lines) lines):\n\(output)"
    }

    private func handleListPanes(context: ToolContext) -> String {
        guard let compositeContext = context.conversation.buildCompositeContext() else {
            return "Panes: 1 (focused)\nCWD: \(context.focusedPane.currentDirectory ?? "unknown")"
        }
        var lines: [String] = ["Panes in this tab:\n"]
        for pane in compositeContext.panes {
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

    private func handleGetPaneState(_ args: [String: Any], context: ToolContext) -> String {
        let paneNum = args["pane"] as? Int ?? 1
        let resolved = context.conversation.resolvePane(number: paneNum)
        if let pane = resolved?.pane {
            return paneStateOutput(pane: pane, label: resolved?.label ?? "Pane \(paneNum)")
        } else {
            return "Pane \(paneNum) not found."
        }
    }

    private func handleSendKeys(_ args: [String: Any], context: ToolContext) -> String {
        guard let keys = args["keys"] as? String else {
            return "Missing 'keys' parameter"
        }
        let paneNum = args["pane"] as? Int
        let resolved = context.conversation.resolvePane(number: paneNum)
        let pane = resolved?.pane ?? context.focusedPane
        let label = resolved?.label ?? "focused pane"

        let mapped: String
        switch keys.lowercased() {
        case "ctrl+c", "ctrl-c": mapped = "\u{03}"
        case "ctrl+d", "ctrl-d": mapped = "\u{04}"
        case "ctrl+z", "ctrl-z": mapped = "\u{1A}"
        case "ctrl+l", "ctrl-l": mapped = "\u{0C}"
        case "enter", "return": mapped = "\n"
        case "tab": mapped = "\t"
        case "escape", "esc": mapped = "\u{1B}"
        case "up": mapped = "\u{1B}[A"
        case "down": mapped = "\u{1B}[B"
        case "left": mapped = "\u{1B}[D"
        case "right": mapped = "\u{1B}[C"
        default: mapped = keys
        }
        pane.terminalView.send(data: Array(mapped.utf8)[...])
        return "Sent '\(keys)' to \(label)"
    }

    // MARK: - Helpers

    func readTerminalOutput(pane: PaneController, lines: Int) -> String {
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

    func paneStateOutput(pane: PaneController, label: String) -> String {
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
}
