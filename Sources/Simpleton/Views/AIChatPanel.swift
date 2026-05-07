// Sources/Simpleton/Views/AIChatPanel.swift
import AppKit
import SwiftUI

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: String // "user" or "assistant"
    var content: String
    let timestamp = Date()
}

/// SwiftUI view for the AI Chat Panel.
struct AIChatPanelView: View {
    let aiService: AIService
    let contextProvider: () -> AIContext
    let onInsertCommand: (String) -> Void
    let onDismiss: () -> Void

    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var isStreaming = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text("AI Assistant")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color(nsColor: NSColor(white: 0.08, alpha: 1)))

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            ChatBubble(message: message, onInsertCommand: onInsertCommand)
                                .id(message.id)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            // Input
            HStack(spacing: 8) {
                TextField("Ask about your terminal session...", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit { sendMessage() }
                    .disabled(isStreaming)

                if isStreaming {
                    Button(action: { aiService.cancelAll(); isStreaming = false }) {
                        Image(systemName: "stop.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(input.isEmpty ? .secondary : .purple)
                    }
                    .buttonStyle(.plain)
                    .disabled(input.isEmpty)
                }
            }
            .padding(12)
            .background(Color(nsColor: NSColor(white: 0.08, alpha: 1)))
        }
        .frame(width: 320)
        .background(Color(nsColor: NSColor(white: 0.06, alpha: 1)))
    }

    private func sendMessage() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""

        messages.append(ChatMessage(role: "user", content: text))
        messages.append(ChatMessage(role: "assistant", content: ""))
        isStreaming = true

        let context = contextProvider()
        let system = """
        You are a helpful terminal assistant. The user is working in a terminal emulator.
        \(AIContextBuilder.formatForPrompt(context))

        When suggesting commands, wrap them in backticks like `command here`.
        Keep responses concise and practical.
        """

        Task {
            do {
                let stream = aiService.stream(system: system, user: text, options: AIOptions(maxTokens: 1000, temperature: 0.3))
                for try await token in stream {
                    if let lastIndex = messages.indices.last, messages[lastIndex].role == "assistant" {
                        messages[lastIndex].content += token
                    }
                }
            } catch {
                if let lastIndex = messages.indices.last, messages[lastIndex].role == "assistant" {
                    messages[lastIndex].content += "\n\n*Error: \(error.localizedDescription)*"
                }
            }
            isStreaming = false
        }
    }
}

struct ChatBubble: View {
    let message: ChatMessage
    let onInsertCommand: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: message.role == "user" ? "person.circle" : "sparkles")
                    .font(.system(size: 10))
                    .foregroundColor(message.role == "user" ? .blue : .purple)
                Text(message.role == "user" ? "You" : "AI")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
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
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8)
        .background(message.role == "user" ? Color.blue.opacity(0.05) : Color.clear)
        .cornerRadius(8)
    }

    private func makeAttributedContent(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    private func extractCommands(from text: String) -> [String] {
        let pattern = "`([^`]+)`"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsString = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
        return matches.compactMap { match -> String? in
            guard match.numberOfRanges >= 2 else { return nil }
            let cmd = nsString.substring(with: match.range(at: 1))
            // Only return things that look like commands (not single words)
            return cmd.contains(" ") || cmd.hasPrefix("/") || cmd.hasPrefix("$") ? cmd : nil
        }
    }
}

/// NSViewController host for the AI Chat Panel.
final class AIChatPanelController: NSViewController {

    private let aiService: AIService
    var contextProvider: (() -> AIContext)?
    var onInsertCommand: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    init(aiService: AIService) {
        self.aiService = aiService
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let chatView = AIChatPanelView(
            aiService: aiService,
            contextProvider: { [weak self] in self?.contextProvider?() ?? AIContext(os: "macOS", recentCommands: []) },
            onInsertCommand: { [weak self] cmd in self?.onInsertCommand?(cmd) },
            onDismiss: { [weak self] in self?.onDismiss?() }
        )
        self.view = NSHostingView(rootView: chatView)
        self.view.frame = NSRect(x: 0, y: 0, width: 320, height: 600)
    }
}
