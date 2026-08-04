// Sources/Simpleton/AI/ProviderPreset.swift
import Foundation
import SimpletonCore

/// How the chat requests are spoken to a provider.
enum ProviderTransport {
    /// Native Anthropic Messages API (`AnthropicProvider`).
    case anthropicNative
    /// OpenAI-compatible Chat Completions API (`OpenAIProvider` with a base URL).
    case openAICompatible
}

/// Everything provider-specific in one place, so adding a provider is a single table row
/// rather than edits scattered across services and the settings UI.
struct ProviderPreset {
    let provider: AIProvider
    let displayName: String
    let transport: ProviderTransport
    /// Fixed API base URL for hosted OpenAI-compatible providers. `nil` for Ollama/Custom,
    /// which derive their base URL from user-editable config fields.
    let fixedBaseURL: String?
    let keyPageURL: String?
    let keyDescription: String
    let apiKeyPlaceholder: String
    let defaultModel: String
    let modelHint: String
    /// Native OpenAI-style tool calling. Providers without it fall back to fenced `run` blocks.
    let supportsTools: Bool
    /// Whether an API key is required (false for local Ollama).
    let requiresKey: Bool
    /// Shape of this provider's "list models" endpoint.
    let modelListFormat: AIModelListFormat

    /// The chat API base URL for the current config (resolves Ollama/Custom user fields).
    func chatBaseURL(config: AIConfig) -> String {
        switch provider {
        case .ollama:
            return config.localOllamaURL.trimmingTrailingSlash + "/v1"
        case .custom:
            return (config.baseURL?.trimmingTrailingSlash).flatMap { $0.isEmpty ? nil : $0 }
                ?? "http://localhost:8080/v1"
        default:
            return fixedBaseURL ?? "https://api.openai.com/v1"
        }
    }
}

extension AIProvider {
    /// The preset describing this provider.
    var preset: ProviderPreset {
        switch self {
        case .anthropic:
            return ProviderPreset(
                provider: .anthropic, displayName: "Anthropic (Claude)", transport: .anthropicNative,
                fixedBaseURL: nil, keyPageURL: "https://console.anthropic.com/settings/keys",
                keyDescription: "Create a key at console.anthropic.com", apiKeyPlaceholder: "sk-ant-api03-…",
                defaultModel: "claude-sonnet-4-20250514",
                modelHint: "e.g. claude-sonnet-4 (fast) or claude-opus-4 (most capable)",
                supportsTools: true, requiresKey: true, modelListFormat: .anthropic)
        case .openai:
            return ProviderPreset(
                provider: .openai, displayName: "OpenAI (GPT)", transport: .openAICompatible,
                fixedBaseURL: "https://api.openai.com/v1", keyPageURL: "https://platform.openai.com/api-keys",
                keyDescription: "Create a key at platform.openai.com/api-keys", apiKeyPlaceholder: "sk-proj-…",
                defaultModel: "gpt-4o", modelHint: "e.g. gpt-4o (balanced) or gpt-4o-mini (fast & cheap)",
                supportsTools: true, requiresKey: true, modelListFormat: .openAI)
        case .openrouter:
            return ProviderPreset(
                provider: .openrouter, displayName: "OpenRouter", transport: .openAICompatible,
                fixedBaseURL: "https://openrouter.ai/api/v1", keyPageURL: "https://openrouter.ai/keys",
                keyDescription: "One key for hundreds of models — openrouter.ai/keys", apiKeyPlaceholder: "sk-or-…",
                defaultModel: "openai/gpt-4o-mini",
                modelHint: "Namespaced, e.g. anthropic/claude-sonnet-4 or meta-llama/llama-3.3-70b-instruct",
                supportsTools: true, requiresKey: true, modelListFormat: .openAI)
        case .groq:
            return ProviderPreset(
                provider: .groq, displayName: "Groq", transport: .openAICompatible,
                fixedBaseURL: "https://api.groq.com/openai/v1", keyPageURL: "https://console.groq.com/keys",
                keyDescription: "Create a key at console.groq.com/keys", apiKeyPlaceholder: "gsk_…",
                defaultModel: "llama-3.3-70b-versatile", modelHint: "e.g. llama-3.3-70b-versatile (fast)",
                supportsTools: true, requiresKey: true, modelListFormat: .openAI)
        case .together:
            return ProviderPreset(
                provider: .together, displayName: "Together AI", transport: .openAICompatible,
                fixedBaseURL: "https://api.together.xyz/v1", keyPageURL: "https://api.together.ai/settings/api-keys",
                keyDescription: "Create a key at api.together.ai", apiKeyPlaceholder: "API key",
                defaultModel: "meta-llama/Llama-3.3-70B-Instruct-Turbo",
                modelHint: "Namespaced, e.g. meta-llama/Llama-3.3-70B-Instruct-Turbo",
                supportsTools: true, requiresKey: true, modelListFormat: .openAI)
        case .mistral:
            return ProviderPreset(
                provider: .mistral, displayName: "Mistral", transport: .openAICompatible,
                fixedBaseURL: "https://api.mistral.ai/v1", keyPageURL: "https://console.mistral.ai/api-keys",
                keyDescription: "Create a key at console.mistral.ai", apiKeyPlaceholder: "API key",
                defaultModel: "mistral-large-latest", modelHint: "e.g. mistral-large-latest or codestral-latest",
                supportsTools: true, requiresKey: true, modelListFormat: .openAI)
        case .deepseek:
            return ProviderPreset(
                provider: .deepseek, displayName: "DeepSeek", transport: .openAICompatible,
                fixedBaseURL: "https://api.deepseek.com/v1", keyPageURL: "https://platform.deepseek.com/api_keys",
                keyDescription: "Create a key at platform.deepseek.com", apiKeyPlaceholder: "sk-…",
                defaultModel: "deepseek-chat", modelHint: "e.g. deepseek-chat or deepseek-reasoner",
                supportsTools: true, requiresKey: true, modelListFormat: .openAI)
        case .ollama:
            return ProviderPreset(
                provider: .ollama, displayName: "Ollama (Local)", transport: .openAICompatible,
                fixedBaseURL: nil, keyPageURL: nil,
                keyDescription: "", apiKeyPlaceholder: "",
                defaultModel: "llama3", modelHint: "Local models from `ollama pull` — e.g. llama3, qwen2.5-coder",
                supportsTools: false, requiresKey: false, modelListFormat: .ollamaTags)
        case .custom:
            return ProviderPreset(
                provider: .custom, displayName: "Custom (OpenAI-compatible)", transport: .openAICompatible,
                fixedBaseURL: nil, keyPageURL: nil,
                keyDescription: "Any OpenAI-compatible endpoint", apiKeyPlaceholder: "API key",
                defaultModel: "gpt-4o", modelHint: "Model name as your provider expects it",
                supportsTools: false, requiresKey: false, modelListFormat: .openAI)
        }
    }
}

private extension String {
    var trimmingTrailingSlash: String {
        var s = self
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
