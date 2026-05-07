// Sources/Simpleton/AI/AIService.swift
import Foundation

struct AIOptions {
    var maxTokens: Int = 1000
    var temperature: Double = 0.3
}

/// Centralized AI service. All AI calls go through this.
final class AIService {

    private var config: AIConfig
    private var currentTasks: [Task<Void, Never>] = []

    init(config: AIConfig) {
        self.config = config
    }

    func updateConfig(_ config: AIConfig) {
        self.config = config
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

    /// Cancel all in-flight requests.
    func cancelAll() {
        currentTasks.forEach { $0.cancel() }
        currentTasks.removeAll()
    }

    private func resolveProvider() -> AIProviderProtocol {
        switch config.provider {
        case .anthropic:
            let key = AIKeychain.retrieveAPIKey(for: .anthropic) ?? ""
            return AnthropicProvider(apiKey: key)
        case .openai:
            let key = AIKeychain.retrieveAPIKey(for: .openai) ?? ""
            return OpenAIProvider(apiKey: key, baseURL: "https://api.openai.com/v1")
        case .ollama:
            return OpenAIProvider(apiKey: "", baseURL: config.localOllamaURL + "/v1")
        case .custom:
            let key = AIKeychain.retrieveAPIKey(for: .custom) ?? ""
            return OpenAIProvider(apiKey: key, baseURL: config.baseURL ?? "http://localhost:8080/v1")
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
}
