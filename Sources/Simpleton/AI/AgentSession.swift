// Sources/Simpleton/AI/AgentSession.swift
import Foundation
import AppKit
import SimpletonCore

enum AutopilotMode: String, Codable {
    case off       // approve every command
    case safe      // auto-approve read-only commands, prompt for writes
    case full      // approve everything (current autopilot=true)
}

struct CommandClassifier {
    static let safePatterns: [String] = [
        "ls", "cat", "head", "tail", "wc", "file", "which", "whoami", "hostname",
        "pwd", "echo", "date", "uptime", "df", "du", "free", "top -l 1",
        "git status", "git log", "git diff", "git branch", "git remote",
        "docker ps", "docker images", "docker logs",
        "npm list", "npm outdated", "cargo check", "swift build",
        "env", "printenv", "id", "uname", "sw_vers",
        "curl -s", "ping -c", "dig", "nslookup", "traceroute",
        "find", "grep", "rg", "fd", "ag",
    ]

    static let unsafeOperators: [String] = ["|", ">", ">>", "<"]

    static func isSafe(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        for op in unsafeOperators {
            if trimmed.contains(op) { return false }
        }
        return safePatterns.contains { pattern in
            trimmed == pattern || trimmed.hasPrefix(pattern + " ") || trimmed.hasPrefix(pattern + "\t")
        }
    }
}

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

    @Published var state: State = .idle
    @Published var stepNumber: Int = 0

    var onMessage: ((ChatMessage) -> Void)?
    /// (cmd, explanation, paneLabel, handler(action, overridePaneID?))
    var onApprovalNeeded: ((String, String, String, @escaping (ApprovalAction, PaneID?) -> Void) -> Void)?
    /// (cmd, output, paneLabel)
    var onCommandExecuted: ((String, String, String) -> Void)?
    var onComplete: (() -> Void)?
    var onError: ((String) -> Void)?

    private let aiService: AIService
    private let processRunner = ProcessRunner()
    private let promptBuilder = PromptBuilder()
    private let toolRegistry: ToolHandlerRegistry
    var isCancelled = false
    var pendingApprovalContinuation: CheckedContinuation<(ApprovalAction, PaneID?), Never>?
    private var turnCount = 0
    var maxTurns = 25
    private var warningTurn: Int { max(maxTurns - 10, 10) }

    init(aiService: AIService) {
        self.aiService = aiService
        self.toolRegistry = ToolHandlerRegistry([
            FileTools(), TerminalTools(), GitTools(),
            SystemTools(), NetworkTools(), ProcessTools(),
        ])
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
        autopilotMode: AutopilotMode
    ) async {
        isCancelled = false
        turnCount = 0
        stepNumber = 0
        var turns = history
        turns.append(.user(message))

        while !isCancelled {
            turnCount += 1
            if turnCount > maxTurns {
                onMessage?(ChatMessage(role: "assistant", content: "Reached the maximum number of steps (\(maxTurns)). Stopping to avoid runaway execution. Here's what was accomplished so far."))
                state = .done
                onComplete?()
                return
            }

            // Inject soft warning near the limit
            var turnOptions = AIOptions(maxTokens: 4000, temperature: 0.3)
            var effectiveSystem = systemPrompt
            if turnCount == warningTurn {
                effectiveSystem += "\n\n[SYSTEM NOTE: You are approaching the step limit (\(maxTurns)). Start wrapping up — finish the current task and provide a summary.]"
            }

            state = .streaming
            do {
                let result = try await aiService.agentTurn(system: effectiveSystem, turns: turns, options: turnOptions)
                switch result {
                case .text(let text):
                    onMessage?(ChatMessage(role: "assistant", content: text))
                    state = .done
                    onComplete?()
                    return

                case .toolCall(let id, let name, let args):
                    if name == "run_command" { stepNumber += 1 }
                    let result = await handleToolCall(
                        id: id, name: name, args: args,
                        conversation: conversation, focusedPane: focusedPane,
                        autopilotMode: autopilotMode, turns: &turns
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

    /// Dispatch a tool call to the appropriate handler.
    private func handleToolCall(
        id: String, name: String, args: [String: Any],
        conversation: TabConversation, focusedPane: PaneController,
        autopilotMode: AutopilotMode, turns: inout [ConversationTurn]
    ) async -> ToolHandleResult {
        if name == "run_command" {
            return await handleRunCommand(
                id: id, args: args, conversation: conversation,
                focusedPane: focusedPane, autopilotMode: autopilotMode, turns: &turns
            )
        }

        let context = ToolContext(conversation: conversation, focusedPane: focusedPane, processRunner: processRunner)
        if let handler = toolRegistry.handler(for: name) {
            let output = await handler.handle(name: name, args: args, context: context)
            turns.append(.toolResult(toolCallID: id, output: output))
            return .continued
        }

        turns.append(.toolResult(toolCallID: id, output: "Unknown tool: \(name)"))
        return .continued
    }

    // MARK: - Skill Execution (Multi-Pane)

    func run(skill: Skill, params: [String: String], conversation: TabConversation, focusedPane: PaneController, autopilotMode: AutopilotMode) async {
        isCancelled = false
        let system = promptBuilder.buildSystemPrompt(skill: skill, params: params, conversation: conversation, focusedPane: focusedPane)
        let initialMessage = "Run the \(skill.name) skill.\(promptBuilder.buildParamSummary(params: params))"
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
                        autopilotMode: autopilotMode, turns: &turns
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

    func run(skill: Skill, params: [String: String], pane: PaneController, autopilotMode: AutopilotMode) async {
        isCancelled = false
        let system = promptBuilder.buildSystemPromptLegacy(skill: skill, params: params, pane: pane)
        let initialMessage = "Run the \(skill.name) skill.\(promptBuilder.buildParamSummary(params: params))"
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
                    if autopilotMode == .full {
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

}
