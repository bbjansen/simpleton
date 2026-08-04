// Sources/SimpletonCore/Core/AIModelListParser.swift
import Foundation

/// The JSON shape a provider's "list models" endpoint returns.
public enum AIModelListFormat: Sendable {
    /// OpenAI-compatible: `{ "data": [ { "id": "..." }, ... ] }` (OpenAI, OpenRouter, Groq, …).
    case openAI
    /// Ollama `/api/tags`: `{ "models": [ { "name": "..." }, ... ] }`.
    case ollamaTags
    /// Anthropic `/v1/models`: `{ "data": [ { "id": "..." }, ... ] }` (same shape as OpenAI).
    case anthropic
}

/// Pure parser that turns a provider's model-list JSON into model identifiers.
/// Kept free of networking so it can be unit-tested without a live endpoint.
public enum AIModelListParser {
    /// Parse model-list JSON into a de-duplicated list of model identifiers, preserving the
    /// order the provider returned them in. Returns an empty array on any malformed input.
    public static func parse(_ data: Data, format: AIModelListFormat) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        let raw: [String]
        switch format {
        case .openAI, .anthropic:
            let arr = root["data"] as? [[String: Any]] ?? []
            raw = arr.compactMap { $0["id"] as? String }
        case .ollamaTags:
            let arr = root["models"] as? [[String: Any]] ?? []
            raw = arr.compactMap { $0["name"] as? String }
        }
        // De-duplicate while preserving first-seen order.
        var seen = Set<String>()
        return raw.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
