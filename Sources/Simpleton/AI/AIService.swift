// Sources/Simpleton/AI/AIService.swift
import Foundation

struct AIOptions {
    var maxTokens: Int = 1000
    var temperature: Double = 0.3
}

// MARK: - Agent Conversation Types

struct ConversationTurn {
    enum Role {
        case user(String)
        case assistant(String)
        case toolResult(toolCallID: String, output: String)
    }
    let role: Role

    static func user(_ text: String) -> ConversationTurn { .init(role: .user(text)) }
    static func assistant(_ text: String) -> ConversationTurn { .init(role: .assistant(text)) }
    static func toolResult(toolCallID: String, output: String) -> ConversationTurn {
        .init(role: .toolResult(toolCallID: toolCallID, output: output))
    }
}

enum AgentTurnResult {
    case text(String)
    case toolCall(id: String, name: String, arguments: [String: Any])
}

extension AgentTurnResult {
    /// Convenience for the common run_command case
    var asRunCommand: (id: String, cmd: String, explanation: String)? {
        guard case .toolCall(let id, let name, let args) = self, name == "run_command",
            let cmd = args["cmd"] as? String
        else { return nil }
        return (id, cmd, args["explanation"] as? String ?? "")
    }
}

/// Centralized AI service. All AI calls go through this.
final class AIService {

    private var config: AIConfig
    private var currentTasks: [Task<Void, Never>] = []

    /// The API key, cached after the first Keychain read. Without this, `resolveProvider()` hit the
    /// Keychain on EVERY request — and with a self-signed (untrusted) code-signing cert macOS won't
    /// let "Always Allow" stick, so each read re-prompted for the login password. Cached here, a
    /// session prompts at most once. Invalidated whenever the config (possibly the key) changes.
    private var cachedKey: String?
    private var cachedKeyProvider: AIProvider?

    init(config: AIConfig) {
        self.config = config
    }

    func updateConfig(_ config: AIConfig) {
        self.config = config
        cachedKey = nil
        cachedKeyProvider = nil
    }

    var isEnabled: Bool { config.enabled }

    /// Non-streaming completion.
    func complete(system: String, user: String, options: AIOptions = AIOptions()) async throws -> String {
        guard config.enabled else { throw AIError.disabled }
        let provider = resolveProvider()
        return try await provider.complete(system: system, user: user, model: config.model, options: options)
    }

    /// Streaming completion — yields tokens as they arrive.
    func stream(system: String, user: String, options: AIOptions = AIOptions()) -> AsyncThrowingStream<String, Error> {
        guard config.enabled else {
            return AsyncThrowingStream { $0.finish(throwing: AIError.disabled) }
        }
        let provider = resolveProvider()
        return provider.stream(system: system, user: user, model: config.model, options: options)
    }

    var supportsToolUse: Bool { config.provider.preset.supportsTools }

    func agentTurn(
        system: String,
        turns: [ConversationTurn],
        options: AIOptions = AIOptions(maxTokens: 4000, temperature: 0.2)
    ) async throws -> AgentTurnResult {
        guard config.enabled else { throw AIError.disabled }
        let provider = resolveProvider()

        if supportsToolUse {
            return try await provider.completeWithTools(
                system: system, turns: turns, model: config.model, options: options
            )
        } else {
            // Fenced-block mode for Ollama/Custom
            var messages: [String] = []
            for turn in turns {
                switch turn.role {
                case .user(let text): messages.append(text)
                case .assistant: break
                case .toolResult(_, let output): messages.append("Command output:\n\(output)")
                }
            }
            let combined = messages.joined(separator: "\n\n")
            let text = try await provider.complete(
                system: system, user: combined, model: config.model, options: options)
            if let cmd = parseFencedRunBlock(from: text) {
                return .toolCall(
                    id: UUID().uuidString, name: "run_command", arguments: ["cmd": cmd, "explanation": ""])
            }
            return .text(text)
        }
    }

    private func parseFencedRunBlock(from text: String) -> String? {
        guard let start = text.range(of: "```run\n"),
            let end = text.range(of: "\n```", range: start.upperBound..<text.endIndex)
        else { return nil }
        return String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cancel all in-flight requests.
    func cancelAll() {
        currentTasks.forEach { $0.cancel() }
        currentTasks.removeAll()
    }

    private func resolveProvider() -> AIProviderProtocol {
        let preset = config.provider.preset
        let key: String
        if let cached = cachedKey, cachedKeyProvider == config.provider {
            key = cached
        } else {
            key = AIKeychain.retrieveAPIKey(for: config.provider) ?? ""
            // Only cache a successful read — a dismissed/failed prompt returns "" and must not get
            // stuck for the whole session.
            if !key.isEmpty {
                cachedKey = key
                cachedKeyProvider = config.provider
            }
        }
        switch preset.transport {
        case .anthropicNative:
            return AnthropicProvider(apiKey: key)
        case .openAICompatible:
            return OpenAIProvider(apiKey: key, baseURL: preset.chatBaseURL(config: config))
        }
    }
}

enum AIError: Error, LocalizedError {
    case disabled
    case noAPIKey
    case networkError(String)
    case invalidResponse
    case providerError(String)

    var errorDescription: String? {
        switch self {
        case .disabled: return "AI features are disabled. Enable in Preferences > AI."
        case .noAPIKey: return "No API key configured. Add one in Preferences > AI."
        case .networkError(let msg): return "Network error: \(msg)"
        case .invalidResponse: return "Invalid response from AI provider."
        case .providerError(let msg): return msg
        }
    }
}

/// Protocol for AI providers (Anthropic, OpenAI, Ollama).
protocol AIProviderProtocol {
    func complete(system: String, user: String, model: String, options: AIOptions) async throws -> String
    func stream(system: String, user: String, model: String, options: AIOptions) -> AsyncThrowingStream<String, Error>
    func completeWithTools(
        system: String, turns: [ConversationTurn], model: String, options: AIOptions
    ) async throws -> AgentTurnResult
}

extension AIProviderProtocol {
    func completeWithTools(
        system: String, turns: [ConversationTurn], model: String, options: AIOptions
    ) async throws -> AgentTurnResult {
        throw AIError.invalidResponse
    }
}
