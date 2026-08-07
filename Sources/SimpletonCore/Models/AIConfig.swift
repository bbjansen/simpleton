// Sources/SimpletonCore/Models/AIConfig.swift
import Foundation

/// AI provider + model selection. Lives in SimpletonCore (not the app target) so a Workspace can
/// carry an `AIConfig?` as part of its saved setup — SimpletonCore is the shared model layer the app
/// depends on, and the model layer can't reach back into the app target.
public enum AIProvider: String, Codable, CaseIterable {
    case anthropic
    case openai
    case openrouter
    case groq
    case together
    case mistral
    case deepseek
    case ollama
    case custom
}

public struct AIConfig: Codable, Equatable {
    public var enabled: Bool
    public var provider: AIProvider
    public var baseURL: String?
    public var model: String
    public var localOllamaURL: String

    public init(
        enabled: Bool = false,
        provider: AIProvider = .anthropic,
        baseURL: String? = nil,
        model: String = "claude-sonnet-4-20250514",
        localOllamaURL: String = "http://localhost:11434"
    ) {
        self.enabled = enabled
        self.provider = provider
        self.baseURL = baseURL
        self.model = model
        self.localOllamaURL = localOllamaURL
    }
}

public struct AIConfigFile: Codable {
    public let version: Int
    public var config: AIConfig

    public init(version: Int = 1, config: AIConfig = AIConfig()) {
        self.version = version
        self.config = config
    }
}
