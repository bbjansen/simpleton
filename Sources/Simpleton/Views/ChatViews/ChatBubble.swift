// Sources/Simpleton/Views/ChatViews/ChatBubble.swift
import SwiftUI

struct ChatBubble: View {
    let message: ChatMessage
    let onInsertCommand: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: message.role == "user" ? "person.circle" : "sparkles")
                    .font(.system(size: 10))
                    .foregroundColor(message.role == "user" ? DT.accentBlue : DT.accent)
                Text(message.role == "user" ? "You" : "AI")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DT.textSecondary)
            }

            // Parse content for inline code blocks
            Text(makeAttributedContent(message.content))
                .font(.system(size: 12))
                .textSelection(.enabled)

            // Extract commands (backtick-wrapped) and show insert buttons
            let commands = extractCommands(from: message.content)
            if !commands.isEmpty && message.role == "assistant" {
                ForEach(commands, id: \.self) { cmd in
                    Button(action: { onInsertCommand(cmd) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "terminal")
                                .font(.system(size: 9))
                            Text(cmd)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                            Spacer()
                            Text("Insert")
                                .font(.system(size: 9))
                        }
                        .padding(6)
                        .background(DT.accent.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8)
        .background(message.role == "user" ? DT.accentBlue.opacity(0.05) : Color.clear)
        .cornerRadius(8)
    }

    private func makeAttributedContent(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    private func extractCommands(from text: String) -> [String] {
        var results: [String] = []
        var seen = Set<String>()

        // 1. Triple-backtick code blocks: every non-empty, non-comment line is a command.
        //    Match ``` optionally followed by a language tag, then capture the body.
        let fencePattern = "```[a-zA-Z0-9]*\\n([\\s\\S]*?)```"
        if let fenceRE = try? NSRegularExpression(pattern: fencePattern) {
            let ns = text as NSString
            let fullRange = NSRange(location: 0, length: ns.length)
            for m in fenceRE.matches(in: text, range: fullRange) {
                guard m.numberOfRanges >= 2 else { continue }
                let body = ns.substring(with: m.range(at: 1))
                for line in body.components(separatedBy: "\n") {
                    let cmd = line.trimmingCharacters(in: .whitespaces)
                    guard !cmd.isEmpty, !cmd.hasPrefix("#"), seen.insert(cmd).inserted else { continue }
                    results.append(cmd)
                }
            }
        }

        // 2. Inline single-backtick spans — strip code-block regions first so
        //    the opening/closing fence backticks don't confuse the inline regex.
        var stripped = text
        if let fenceRE = try? NSRegularExpression(pattern: "```[\\s\\S]*?```") {
            stripped = fenceRE.stringByReplacingMatches(
                in: stripped,
                range: NSRange(location: 0, length: (stripped as NSString).length),
                withTemplate: ""
            )
        }

        let inlinePattern = "`([^`\\n]+)`"
        if let inlineRE = try? NSRegularExpression(pattern: inlinePattern) {
            let ns = stripped as NSString
            for m in inlineRE.matches(in: stripped, range: NSRange(location: 0, length: ns.length)) {
                guard m.numberOfRanges >= 2 else { continue }
                let cmd = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
                guard isRunnableCommand(cmd), seen.insert(cmd).inserted else { continue }
                results.append(cmd)
            }
        }

        return results
    }

    /// Returns true when an inline backtick span looks like a runnable shell command
    /// (multi-word, starts with a command name, not an English sentence fragment).
    private func isRunnableCommand(_ text: String) -> Bool {
        guard text.contains(" ") else { return false }
        let first = text.components(separatedBy: " ").first ?? ""
        guard !first.isEmpty else { return false }
        // Must start with a lowercase letter (command name) or common prefixes
        guard
            first.first?.isLowercase == true
                || text.hasPrefix("./") || text.hasPrefix("~/")
        else { return false }
        // Skip common English sentence-starter words that aren't commands
        let prose: Set<String> = [
            "you", "the", "this", "that", "it", "if", "in", "on", "at", "to", "a",
            "an", "and", "or", "for", "of", "with", "by", "from", "make", "note",
            "use", "run", "check", "see", "also", "ensure", "when", "where", "then",
            "just", "now", "here", "these", "those", "both", "all", "each",
        ]
        return !prose.contains(first.lowercased())
    }
}
