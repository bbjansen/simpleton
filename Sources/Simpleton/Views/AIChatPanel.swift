// Sources/Simpleton/Views/AIChatPanel.swift
import AppKit
import SwiftUI
import SimpletonCore

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: String // "user" or "assistant"
    var content: String
    let timestamp = Date()
}

enum AgentUIMessage: Identifiable {
    case chat(ChatMessage)
    case execution(id: UUID, cmd: String, explanation: String, status: AgentExecutionBubble.BubbleStatus, output: String)

    var id: UUID {
        switch self {
        case .chat(let m): return m.id
        case .execution(let id, _, _, _, _): return id
        }
    }
}

/// SwiftUI view for the AI Chat Panel.
struct AIChatPanelView: View {
    let aiService: AIService
    let contextProvider: () -> AIContext
    let onInsertCommand: (String) -> Void
    var onDismiss: (() -> Void)?

    var skillStore: SkillStore?
    var currentPaneProvider: (() -> PaneController?)?

    private var currentPane: PaneController? { currentPaneProvider?() }

    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var isStreaming = false

    @State private var autopilotEnabled = false
    @State private var showSkillPicker = false
    @State private var activeSkill: Skill? = nil
    @State private var skillValues: [String: String] = [:]
    @State private var aiSuggestedKeys: Set<String> = []
    @State private var agentBubbles: [AgentUIMessage] = []
    @State private var activeAgentSession: AgentSession? = nil
    @State private var pendingApprovals: [UUID: (AgentSession.ApprovalAction) -> Void] = [:]
    @State private var selectedPaneID: PaneID? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text("AI Assistant")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle(isOn: $autopilotEnabled) {
                    Text("Autopilot")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(autopilotEnabled ? .white : .secondary)
                }
                .toggleStyle(.button)
                .controlSize(.mini)
                .tint(.purple)
                if let dismiss = onDismiss {
                    Button(action: dismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color(nsColor: NSColor(white: 0.08, alpha: 1)))

            Divider()

            // Skill parameter form overlay (shown when a skill is selected)
            if let skill = activeSkill {
                let paneList: [(id: PaneID, label: String)] = {
                    if let pane = currentPane { return [(id: pane.id, label: "Current pane")] }
                    return []
                }()
                SkillParameterForm(
                    skill: skill,
                    values: $skillValues,
                    aiSuggestedKeys: aiSuggestedKeys,
                    panes: paneList,
                    selectedPaneID: $selectedPaneID,
                    onRun: { runSkill() },
                    onCancel: {
                        activeSkill = nil
                        skillValues = [:]
                        aiSuggestedKeys = []
                    },
                    onFilePickerRequested: { paramName in
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            skillValues[paramName] = url.path
                        }
                    }
                )
                .padding(12)

                Divider()
            }

            // Messages + agent bubbles
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            ChatBubble(message: message, onInsertCommand: onInsertCommand)
                                .id(message.id)
                        }
                        ForEach(agentBubbles) { item in
                            switch item {
                            case .execution(let id, let cmd, let explanation, let status, let output):
                                AgentExecutionBubble(
                                    cmd: cmd,
                                    explanation: explanation,
                                    status: status,
                                    output: output,
                                    onAllow: {
                                        pendingApprovals[id]?(.allow)
                                        pendingApprovals.removeValue(forKey: id)
                                        if let idx = agentBubbles.firstIndex(where: { $0.id == id }) {
                                            agentBubbles[idx] = .execution(id: id, cmd: cmd, explanation: explanation, status: .running, output: "")
                                        }
                                    },
                                    onSkip: {
                                        pendingApprovals[id]?(.skip)
                                        pendingApprovals.removeValue(forKey: id)
                                        if let idx = agentBubbles.firstIndex(where: { $0.id == id }) {
                                            agentBubbles[idx] = .execution(id: id, cmd: cmd, explanation: explanation, status: .skipped, output: "")
                                        }
                                    },
                                    onStop: {
                                        pendingApprovals[id]?(.stop)
                                        pendingApprovals.removeValue(forKey: id)
                                        if let idx = agentBubbles.firstIndex(where: { $0.id == id }) {
                                            agentBubbles[idx] = .execution(id: id, cmd: cmd, explanation: explanation, status: .skipped, output: "")
                                        }
                                    }
                                )
                                .id(id)
                            default:
                                EmptyView()
                            }
                        }
                    }
                    .padding(12)
                }
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onChange(of: agentBubbles.count) {
                    if let last = agentBubbles.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            // Input
            HStack(spacing: 8) {
                // Bolt button for skill picker
                Button(action: { showSkillPicker.toggle() }) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.yellow)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSkillPicker, arrowEdge: .top) {
                    if let store = skillStore {
                        SkillPickerSheet(skillStore: store, onSelect: { skill in
                            activeSkill = skill
                            selectedPaneID = currentPane?.id
                            loadAutoFill(skill: skill)
                        }, onDismiss: { showSkillPicker = false })
                    }
                }

                TextField("Ask about your terminal session...", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit { sendMessage() }
                    .disabled(isStreaming)

                if isStreaming {
                    Button(action: {
                        aiService.cancelAll()
                        activeAgentSession?.cancel()
                        isStreaming = false
                    }) {
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
        .onReceive(NotificationCenter.default.publisher(for: .simpletonActivateSkillPicker)) { _ in
            showSkillPicker = true
        }
    }

    private func sendMessage() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Slash-command detection
        if text.hasPrefix("/") {
            let slug = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
            if let skill = skillStore?.skill(forSlug: slug) {
                input = ""
                activeSkill = skill
                selectedPaneID = currentPane?.id
                loadAutoFill(skill: skill)
                return
            }
        }

        input = ""

        messages.append(ChatMessage(role: "user", content: text))
        messages.append(ChatMessage(role: "assistant", content: ""))
        isStreaming = true

        let context = contextProvider()
        var skillsSection = ""
        if let store = skillStore, !store.allSkills.isEmpty {
            let list = store.allSkills.map { "  /\($0.slug) — \($0.name)" }.joined(separator: "\n")
            skillsSection = """


        Available skills (invoke with /slug or the bolt button):
        \(list)
        """
        }
        let system = """
        You are a helpful terminal assistant. The user is working in a terminal emulator.
        \(AIContextBuilder.formatForPrompt(context))\(skillsSection)

        When suggesting terminal commands, always put them in a fenced code block:
        ```bash
        command here
        ```
        Use inline backticks only for referencing command names or flags inline with text.
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

    private func loadAutoFill(skill: Skill) {
        guard let pane = currentPane else { return }
        skillValues = SkillAutoFill.phase1(skill: skill, pane: pane)
        aiSuggestedKeys = []
        Task {
            let suggested = try? await SkillAutoFill.phase2(
                skill: skill, currentValues: skillValues, pane: pane, aiService: aiService
            )
            if let suggested = suggested {
                for (k, v) in suggested where (skillValues[k] ?? "").isEmpty {
                    skillValues[k] = v
                    aiSuggestedKeys.insert(k)
                }
            }
        }
    }

    private func runSkill() {
        guard let skill = activeSkill, let pane = currentPane else { return }
        activeSkill = nil
        let params = skillValues
        skillValues = [:]
        aiSuggestedKeys = []

        let session = AgentSession(aiService: aiService)
        activeAgentSession = session

        let runningID = UUID()
        agentBubbles.append(.execution(id: runningID, cmd: "Starting \(skill.name)…", explanation: "", status: .running, output: ""))

        session.onMessage = { msg in
            messages.append(msg)
        }
        session.onCommandExecuted = { cmd, output in
            if let idx = agentBubbles.indices.last(where: {
                if case .execution(_, _, _, let s, _) = agentBubbles[$0], s == .running { return true }
                return false
            }) {
                if case .execution(let id, let c, let exp, _, _) = agentBubbles[idx] {
                    agentBubbles[idx] = .execution(id: id, cmd: c, explanation: exp, status: .done, output: output)
                }
            }
        }
        session.onComplete = {
            isStreaming = false
            activeAgentSession = nil
        }
        session.onError = { err in
            messages.append(ChatMessage(role: "assistant", content: "Error: \(err)"))
            isStreaming = false
            activeAgentSession = nil
        }
        session.onApprovalNeeded = { cmd, explanation, completion in
            let approvalID = UUID()
            pendingApprovals[approvalID] = completion
            agentBubbles.append(.execution(id: approvalID, cmd: cmd, explanation: explanation, status: .waitingApproval, output: ""))
        }

        isStreaming = true
        Task {
            await session.run(skill: skill, params: params, pane: pane, autopilot: autopilotEnabled)
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
        guard first.first?.isLowercase == true
                || text.hasPrefix("./") || text.hasPrefix("~/") else { return false }
        // Skip common English sentence-starter words that aren't commands
        let prose: Set<String> = [
            "you", "the", "this", "that", "it", "if", "in", "on", "at", "to", "a",
            "an", "and", "or", "for", "of", "with", "by", "from", "make", "note",
            "use", "run", "check", "see", "also", "ensure", "when", "where", "then",
            "just", "now", "here", "these", "those", "both", "all", "each"
        ]
        return !prose.contains(first.lowercased())
    }
}

/// NSViewController host for the AI Chat Panel.
final class AIChatPanelController: NSViewController {

    private let aiService: AIService
    var contextProvider: (() -> AIContext)?
    var onInsertCommand: ((String) -> Void)?
    var onDismiss: (() -> Void)?
    var skillStore: SkillStore?
    var currentPaneProvider: (() -> PaneController?)?

    init(aiService: AIService) {
        self.aiService = aiService
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        var chatView = AIChatPanelView(
            aiService: aiService,
            contextProvider: { [weak self] in self?.contextProvider?() ?? AIContext(os: "macOS", recentCommands: []) },
            onInsertCommand: { [weak self] cmd in self?.onInsertCommand?(cmd) },
            onDismiss: onDismiss.map { _ in { [weak self] in self?.onDismiss?() } }
        )
        chatView.skillStore = skillStore
        chatView.currentPaneProvider = currentPaneProvider
        self.view = NSHostingView(rootView: chatView)
        self.view.frame = NSRect(x: 0, y: 0, width: 320, height: 600)
    }
}
