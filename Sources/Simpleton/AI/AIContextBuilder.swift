// Sources/Simpleton/AI/AIContextBuilder.swift
import Foundation
import SwiftTerm

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
}
