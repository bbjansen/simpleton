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

    /// Per-tab conversation. When set, multi-pane context is used.
    var conversation: TabConversation?

    var memoryStore: MemoryStore?
    var mcpConfigStore: MCPConfigStore?
    var eventBus: WorkspaceEventBus?
    var projectIndexer: ProjectIndexer?

    private var currentPane: PaneController? { currentPaneProvider?() }

    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var isStreaming = false

    @State private var autopilotMode: AutopilotMode = .off
    @State private var showAutopilotConfirm = false
    @State private var showSkillPicker = false
    @State private var activeSkill: Skill? = nil
    @State private var skillValues: [String: String] = [:]
    @State private var aiSuggestedKeys: Set<String> = []
    @State private var agentBubbles: [AgentUIMessage] = []
    @State private var activeAgentSession: AgentSession? = nil
    @State private var pendingApprovals: [UUID: (AgentSession.ApprovalAction) -> Void] = [:]
    @State private var selectedPaneID: PaneID? = nil
    @State private var unlimitedTurns = false
    @State private var watchActive = false
    @State private var mcpClients: [MCPClient] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            ChatHeaderView(
                autopilotMode: $autopilotMode,
                showAutopilotConfirm: $showAutopilotConfirm,
                watchActive: $watchActive,
                onDismiss: onDismiss
            )

            Divider()

            // Autopilot warning banner
            if autopilotMode != .off {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.black)
                    Text(autopilotMode == .full
                         ? "Autopilot FULL — AI executes all commands without approval"
                         : "Autopilot SAFE — read-only commands auto-approved, writes need approval")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.black)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(autopilotMode == .full ? Color.orange : Color.yellow.opacity(0.7))
            }

            // Pane indicator bar (multi-pane only)
            if let conv = conversation, conv.paneOrder.count > 1 {
                PaneIndicatorBar(conversation: conv)
            }

            // Skill parameter form overlay (shown when a skill is selected)
            if let skill = activeSkill {
                let paneList: [(id: PaneID, label: String)] = {
                    if let conv = conversation {
                        return conv.paneOrder.map { id in
                            (id: id, label: conv.paneLabels[id] ?? "Pane")
                        }
                    }
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
            ChatInputView(
                input: $input,
                showSkillPicker: $showSkillPicker,
                isStreaming: isStreaming,
                skillStore: skillStore,
                onSend: sendMessage,
                onCancel: {
                    aiService.cancelAll()
                    activeAgentSession?.cancel()
                    isStreaming = false
                },
                onSkillSelected: { skill in
                    activeSkill = skill
                    selectedPaneID = currentPane?.id
                    loadAutoFill(skill: skill)
                }
            )

            // Bottom status bar: step counter + turn cap toggle
            ChatStatusBar(
                stepNumber: activeAgentSession?.stepNumber ?? 0,
                unlimitedTurns: $unlimitedTurns
            )
        }
        .frame(width: 320)
        .background(Color(nsColor: NSColor(white: 0.06, alpha: 1)))
        .onReceive(NotificationCenter.default.publisher(for: .simpletonActivateSkillPicker)) { _ in
            showSkillPicker = true
        }
        .onChange(of: watchActive) { _, active in
            guard let conv = conversation, let pane = currentPane else {
                watchActive = false
                return
            }
            if active {
                let session = WatchSession(
                    pane: pane,
                    triggers: [.exitCodeNonZero],
                    aiService: aiService,
                    memoryStore: memoryStore
                ) { event in
                    let msg = ChatMessage(role: "assistant", content: "[Watch] \(event)")
                    self.messages.append(msg)
                    conv.messages.append(msg)
                }
                conv.watchSession = session
                session.start()
            } else {
                conv.watchSession?.stop()
                conv.watchSession = nil
            }
        }
    }

    private func configureSession(_ session: AgentSession, conversation: TabConversation?) {
        if unlimitedTurns { session.maxTurns = Int.max }
        activeAgentSession = session

        session.onMessage = { msg in
            messages.append(msg)
            conversation?.messages.append(msg)
        }
        session.onCommandExecuted = { cmd, output, paneLabel in
            if let idx = agentBubbles.indices.last(where: {
                if case .execution(_, _, _, let s, _) = agentBubbles[$0], s == .running { return true }
                return false
            }) {
                if case .execution(let id, _, let exp, _, _) = agentBubbles[idx] {
                    agentBubbles[idx] = .execution(id: id, cmd: cmd, explanation: "[\(paneLabel)] \(exp)", status: .done, output: output)
                }
            }
        }
        session.onComplete = {
            isStreaming = false
            activeAgentSession = nil
            conversation?.activeSession = nil
            conversation?.isRunning = false
            conversation?.watchSession?.resume()
        }
        session.onError = { err in
            let errMsg = ChatMessage(role: "assistant", content: "Error: \(err)")
            messages.append(errMsg)
            conversation?.messages.append(errMsg)
            isStreaming = false
            activeAgentSession = nil
            conversation?.activeSession = nil
            conversation?.isRunning = false
            conversation?.watchSession?.resume()
        }
        session.onApprovalNeeded = { cmd, explanation, paneLabel, completion in
            let approvalID = UUID()
            pendingApprovals[approvalID] = { action in completion(action, nil) }
            agentBubbles.append(.execution(id: approvalID, cmd: cmd, explanation: "[\(paneLabel)] \(explanation)", status: .waitingApproval, output: ""))
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
        isStreaming = true
        conversation?.watchSession?.pause()

        // Capture for async project indexing inside Task blocks
        let indexer = projectIndexer
        let projectDir = currentPane?.currentDirectory

        // Build system prompt with multi-pane context
        let contextStr: String
        if let conv = conversation, let composite = conv.buildCompositeContext() {
            contextStr = AIContextBuilder.formatCompositeForPrompt(composite)
        } else {
            let context = contextProvider()
            contextStr = AIContextBuilder.formatForPrompt(context)
        }
        var skillsSection = ""
        if let store = skillStore, !store.allSkills.isEmpty {
            let list = store.allSkills.map { "  /\($0.slug) — \($0.name)" }.joined(separator: "\n")
            skillsSection = "\n\nAvailable skills (invoke with /slug or the bolt button):\n\(list)"
        }
        // Load project memories for context injection
        var memorySection = ""
        if let store = memoryStore, let pane = currentPane {
            let projectPath = pane.currentDirectory ?? FileManager.default.currentDirectoryPath
            store.loadForProject(path: projectPath)
            let relevant = store.relevantMemories(forContext: "\(contextStr) \(text)")
            if !relevant.isEmpty {
                let memList = relevant.map { "  - \($0.promptSummary)" }.joined(separator: "\n")
                memorySection = "\n\n## Known context (from memory)\n\(memList)"
            }
        }
        var crossTabSection = ""
        if let bus = eventBus, let tabID = conversation?.tabID {
            if let summary = bus.formatForPrompt(excludingTab: tabID) {
                crossTabSection = "\n\n\(summary)"
            }
        }
        let system = """
        You are a powerful terminal agent embedded in a native macOS terminal emulator. You have full access to the user's terminal panes and can execute commands, read output, and orchestrate multi-step workflows.

        \(contextStr)\(skillsSection)\(memorySection)\(crossTabSection)

        ## Your tools
        - **run_command(cmd, pane?)**: Execute shell commands. Target a specific pane by number. Output + exit code are captured automatically.
        - **read_pane_output(pane?, lines?)**: Read recent terminal output without running anything. Default 50 lines, max 200. Check status, errors, or long-running processes.
        - **list_panes()**: See all panes with their CWD, shell, and state.
        - **get_pane_state(pane)**: Detailed pane info including CWD, shell, connection type, recent output.
        - **read_file(path)**: Read a file directly (up to 10k chars). Avoids shell quoting issues.
        - **write_file(path, content)**: Write a file directly. Creates parent directories. Avoids heredoc escaping.
        - **edit_file(path, old_text, new_text, replace_all?, trim_whitespace?)**: Search-and-replace in a file. Safer than write_file for targeted edits. Set trim_whitespace=true to match ignoring whitespace differences.
        - **list_directory(path?)**: List files/dirs with types and sizes. Faster than ls.
        - **search_files(pattern, directory?)**: Recursive grep across files. Find code, config values, etc.
        - **get_git_status(directory?)**: Git status (short format).
        - **get_git_diff(directory?, staged?)**: Git diff summary.
        - **get_git_log(directory?, count?)**: Recent commit history.
        - **clipboard_copy(text)**: Copy text to the system clipboard.
        - **send_keys(keys, pane?)**: Send keystrokes to a pane — ctrl+c, ctrl+d, enter, arrow keys, etc. Use to stop processes, navigate menus, or provide interactive input.
        - **get_env(name?)**: Get one or all environment variables.
        - **http_request(url, method?, headers?, body?)**: Make HTTP requests — test APIs, check endpoints. Headers is a dictionary, body is a string.
        - **check_port(port, host?)**: Check if a port is in use and what process holds it.
        - **find_process(name)**: Find running processes by name.
        - **kill_process(pid, signal?)**: Send signals to processes. Supports: TERM, KILL, INT, HUP, STOP, CONT, USR1, USR2, QUIT.
        - **get_system_info()**: OS, hostname, CPU, memory, uptime, user, shell.
        - **web_search(query, count?)**: Search the web via DuckDuckGo. Returns titles, snippets, and URLs. Default 5 results, max 10.
        - **fetch_url(url)**: Fetch a web page and return text content (HTML stripped, max 5000 chars). Use to read documentation, API responses, etc.
        - **save_memory(content, type, tags)**: Save information to persistent project memory. Types: errorFix, convention, decision, environment, preference. Tags help retrieval.
        - **recall_memory(query, count?)**: Search project memory semantically. Returns the most relevant saved memories. Use when you need to recall past decisions, fixes, or conventions.
        - **list_memories(type?)**: List all saved memories, optionally filtered by type.
        - **forget_memory(id)**: Delete a memory entry by ID (full UUID or first 8 chars).
        - **list_skills(category?)**: List available skills. Optionally filter by keyword. Shows slug, description, and parameters.
        - **run_skill(slug, params?)**: Invoke a skill by its slug (e.g., "system-health"). Pass params as an object. Missing params auto-fill from terminal context. Returns task instructions to execute.

        ## Interactive commands
        Some commands require interactive input (y/n prompts, selection menus, passwords).
        When a command appears to be waiting for input (no new output for several seconds):
        1. Use read_pane_output to check what the command is showing
        2. Use send_keys to send the appropriate response (e.g., "y", "enter", arrow keys)
        3. For password prompts: STOP and tell the user — never type passwords

        Common patterns:
        - "y/n" or "[Y/n]" prompts: send_keys with "y" then "enter"
        - "Press any key": send_keys with "enter"
        - Arrow-key menus: send_keys with "up"/"down" then "enter"
        - "password:" or "Password:": STOP immediately, ask the user to enter it manually

        ## How to act
        - When the user asks you to DO something (install, run, fix, deploy, set up, create files, etc.), use your tools to execute it directly. Don't just suggest — act.
        - ALWAYS use run_command to execute commands. NEVER suggest commands in code blocks when you can execute them directly. The user expects action, not suggestions.
        - When there are multiple panes, target the right one based on CWD context.
        - Chain tools across panes: start a server in pane 1, read_pane_output to confirm it's ready, then run tests in pane 2.
        - After running a command, check the exit code. If non-zero, read the output, diagnose, and retry with a fix (up to 3 attempts per command).
        - Use read_file/write_file for file operations — they're faster and more reliable than shell echo/cat.
        - When answering questions, respond with plain text. Keep it concise.
        \({
            switch autopilotMode {
            case .full:
                return "- AUTOPILOT MODE (FULL): Commands execute immediately without user approval. You have full autonomous control. Execute commands directly — do not ask for permission or confirmation."
            case .safe:
                return "- AUTOPILOT MODE (SAFE): Read-only commands (ls, cat, grep, git status, etc.) execute automatically. Destructive or write commands require user approval."
            case .off:
                return "- Commands require user approval before executing. The user will see each command and can allow, skip, or stop."
            }
        }())
        """

        // Build conversation history as proper turns
        var history: [ConversationTurn] = []
        for msg in messages.dropLast() { // exclude the message we just appended
            let content = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            if msg.role == "user" {
                history.append(.user(content))
            } else {
                history.append(.assistant(content))
            }
        }

        // Use agent session so the AI can execute commands across panes
        if let conv = conversation, let resolved = conv.resolvePane(number: nil) {
            let session = AgentSession(aiService: aiService, memoryStore: memoryStore, skillStore: skillStore, eventBus: eventBus)
            configureSession(session, conversation: conv)
            conv.activeSession = session
            conv.isRunning = true
            Task {
                let projectSection = await Self.buildProjectSection(indexer: indexer, directory: projectDir)
                await session.chat(
                    message: text,
                    history: history,
                    systemPrompt: system + projectSection,
                    conversation: conv,
                    focusedPane: resolved.pane,
                    autopilotMode: autopilotMode
                )
            }
        } else {
            // Fallback: no conversation — use simple streaming (legacy)
            messages.append(ChatMessage(role: "assistant", content: ""))
            Task {
                let projectSection = await Self.buildProjectSection(indexer: indexer, directory: projectDir)
                let enrichedSystem = system + projectSection
                do {
                    let userPrompt: String
                    if !history.isEmpty {
                        var parts: [String] = []
                        for turn in history {
                            switch turn.role {
                            case .user(let t): parts.append("User: \(t)")
                            case .assistant(let t): parts.append("Assistant: \(t)")
                            case .toolResult: break
                            }
                        }
                        userPrompt = "[Previous conversation]\n\(parts.joined(separator: "\n\n"))\n\n[Current message]\n\(text)"
                    } else {
                        userPrompt = text
                    }
                    let stream = aiService.stream(system: enrichedSystem, user: userPrompt, options: AIOptions(maxTokens: 4000, temperature: 0.3))
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
        guard let skill = activeSkill else { return }
        let params = skillValues
        activeSkill = nil
        skillValues = [:]
        aiSuggestedKeys = []

        let session = AgentSession(aiService: aiService, memoryStore: memoryStore, skillStore: skillStore, eventBus: eventBus)

        if let conv = conversation, let resolved = conv.resolvePane(number: nil) {
            configureSession(session, conversation: conv)
            conv.activeSession = session
            let runningID = UUID()
            agentBubbles.append(.execution(id: runningID, cmd: "Starting \(skill.name)...", explanation: "", status: .running, output: ""))
            isStreaming = true
            conv.isRunning = true
            Task {
                await session.run(skill: skill, params: params, conversation: conv, focusedPane: resolved.pane, autopilotMode: autopilotMode)
            }
        } else if let pane = currentPane {
            configureSession(session, conversation: nil)
            let runningID = UUID()
            agentBubbles.append(.execution(id: runningID, cmd: "Starting \(skill.name)...", explanation: "", status: .running, output: ""))
            isStreaming = true
            Task {
                await session.run(skill: skill, params: params, pane: pane, autopilotMode: autopilotMode)
            }
        }
    }

    // MARK: - Project Indexing

    private static func buildProjectSection(indexer: ProjectIndexer?, directory: String?) async -> String {
        guard let indexer, let directory else { return "" }
        guard let index = await indexer.index(for: directory) else { return "" }
        return "\n\n## Project context\n\(index.promptSummary)"
    }
}

