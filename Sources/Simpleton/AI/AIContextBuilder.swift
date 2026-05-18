// Sources/Simpleton/AI/AIContextBuilder.swift
import Foundation
import SwiftTerm
import SimpletonCore

struct AIContext {
    var cwd: String?
    var shell: String?
    var os: String
    var recentCommands: [String]
    var selection: String?
    var recentOutput: String?
}

enum AIContextBuilder {

    /// Build context from the current terminal state.
    static func build(
        terminalView: TerminalView?,
        cwd: String? = nil,
        shell: String? = nil,
        includeSelection: Bool = false,
        recentOutputLines: Int = 50,
        maxOutputChars: Int = 2000
    ) -> AIContext {
        var context = AIContext(
            cwd: cwd,
            shell: shell,
            os: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            recentCommands: [],
            selection: nil,
            recentOutput: nil
        )

        guard let tv = terminalView else { return context }

        // Get selected text if requested
        if includeSelection {
            context.selection = tv.getSelection()
        }

        // Get recent terminal output (last N visible lines)
        let terminal = tv.getTerminal()
        let totalRows = terminal.rows
        let startRow = max(0, totalRows - recentOutputLines)
        var outputLines: [String] = []
        for row in startRow..<totalRows {
            if let line = terminal.getLine(row: row) {
                let text = line.translateToString(trimRight: true)
                if !text.isEmpty {
                    outputLines.append(text)
                }
            }
        }
        let output = outputLines.joined(separator: "\n")
        if output.count > maxOutputChars {
            context.recentOutput = String(output.suffix(maxOutputChars))
        } else {
            context.recentOutput = output
        }

        return context
    }

    /// Format context into a string for inclusion in AI prompts.
    /// Selection takes priority: if the user highlighted text, only that is sent (it's the
    /// explicit signal). Otherwise, recent terminal output is included with blank lines stripped
    /// to maximise signal per token.
    static func formatForPrompt(_ context: AIContext) -> String {
        var parts: [String] = []
        if let cwd = context.cwd { parts.append("Working directory: \(cwd)") }
        if let shell = context.shell { parts.append("Shell: \(shell)") }
        parts.append("OS: \(context.os)")
        if !context.recentCommands.isEmpty {
            parts.append("Recent commands:\n" + context.recentCommands.map { "  $ \($0)" }.joined(separator: "\n"))
        }
        if let selection = context.selection, !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // User selected specific text — highest signal, skip the full output blob
            parts.append("Selected text:\n\(selection)")
        } else if let output = context.recentOutput {
            // Strip blank lines so we pack more meaningful content into fewer tokens
            let stripped = output
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .joined(separator: "\n")
            if !stripped.isEmpty {
                parts.append("Recent terminal output:\n\(stripped)")
            }
        }
        return parts.joined(separator: "\n")
    }

    // MARK: - Composite (Multi-Pane)

    /// Build composite context from all panes in a split controller.
    static func buildComposite(
        splitController: SplitController,
        recentOutputLines: Int = 50,
        maxOutputCharsPerPane: Int = 2000
    ) -> CompositeAIContext {
        let allIDs = splitController.tree.allPaneIDs
        let focusedID = splitController.focusedPaneID

        var snapshots: [PaneSnapshot] = []
        for (index, paneID) in allIDs.enumerated() {
            guard let pane = splitController.panes[paneID] else { continue }

            let singleCtx = build(
                terminalView: pane.terminalView,
                cwd: pane.currentDirectory,
                shell: shellName(for: pane.connectionType),
                includeSelection: false,
                recentOutputLines: recentOutputLines,
                maxOutputChars: maxOutputCharsPerPane
            )

            let label = paneLabel(for: pane, number: index + 1)

            snapshots.append(PaneSnapshot(
                paneID: paneID,
                label: label,
                paneNumber: index + 1,
                cwd: singleCtx.cwd,
                shell: singleCtx.shell,
                recentOutput: singleCtx.recentOutput,
                isFocused: paneID == focusedID,
                connectionType: pane.connectionType
            ))
        }

        return CompositeAIContext(
            os: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            panes: snapshots,
            focusedPaneID: focusedID
        )
    }

    /// Format composite context for inclusion in system prompts.
    static func formatCompositeForPrompt(_ context: CompositeAIContext) -> String {
        if context.panes.count == 1, let pane = context.panes.first {
            let singleCtx = AIContext(
                cwd: pane.cwd,
                shell: pane.shell,
                os: context.os,
                recentCommands: [],
                selection: nil,
                recentOutput: pane.recentOutput
            )
            return formatForPrompt(singleCtx)
        }

        var parts: [String] = []
        parts.append("You have access to \(context.panes.count) terminal panes in this tab:\n")

        for pane in context.panes {
            let focusTag = pane.isFocused ? " (focused)" : ""
            let cwdStr = pane.cwd ?? "unknown"
            let shellStr = pane.shell ?? "shell"
            parts.append("[\(pane.label)]\(focusTag) \(cwdStr) — \(shellStr)")

            if let output = pane.recentOutput {
                let stripped = output
                    .components(separatedBy: "\n")
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    .joined(separator: "\n")
                if !stripped.isEmpty {
                    parts.append("Recent output:\n\(stripped)\n")
                }
            }
        }

        parts.append("When running commands, specify the target pane by number (e.g. pane: 1).")
        parts.append("If you don't specify, commands run on the focused pane (\(context.panes.first(where: { $0.isFocused })?.label ?? "Pane 1")).")

        return parts.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static func shellName(for connectionType: ConnectionType) -> String? {
        switch connectionType {
        case .local(let shell, _):
            return URL(fileURLWithPath: shell).lastPathComponent
        case .ssh:
            return "ssh"
        }
    }

    static func paneLabel(for pane: PaneController, number: Int) -> String {
        switch pane.connectionType {
        case .local:
            if let cwd = pane.currentDirectory {
                let lastComponent = URL(fileURLWithPath: cwd).lastPathComponent
                return "Pane \(number) (\(lastComponent))"
            }
            return "Pane \(number)"
        case .ssh:
            if let host = pane.sshHost {
                return "Pane \(number) (SSH: \(host))"
            }
            return "Pane \(number) (SSH)"
        }
    }
}
