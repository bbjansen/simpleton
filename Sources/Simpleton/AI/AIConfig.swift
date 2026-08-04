// Sources/Simpleton/AI/AIConfig.swift
import Foundation

enum AIProvider: String, Codable, CaseIterable {
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

struct AIConfig: Codable, Equatable {
    var enabled: Bool
    var provider: AIProvider
    var baseURL: String?
    var model: String
    var localOllamaURL: String

    init(
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

struct AIConfigFile: Codable {
    let version: Int
    var config: AIConfig

    init(version: Int = 1, config: AIConfig = AIConfig()) {
        self.version = version
        self.config = config
    }
}
