// Sources/Simpleton/AI/ModelFetcher.swift
import Foundation
import SimpletonCore

/// Fetches the list of available models from a provider's "list models" endpoint.
/// Networking wrapper around the pure `AIModelListParser`.
enum ModelFetcher {

    struct Result {
        let models: [String]
        let error: String?
    }

    static func fetch(config: AIConfig, apiKey: String?) async -> Result {
        guard let request = buildRequest(config: config, apiKey: apiKey) else {
            return Result(models: [], error: "Invalid endpoint URL")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return Result(models: [], error: "No response from server")
            }
            guard (200..<300).contains(http.statusCode) else {
                if http.statusCode == 401 || http.statusCode == 403 {
                    return Result(models: [], error: "Unauthorized — check the API key")
                }
                return Result(models: [], error: "Server returned \(http.statusCode)")
            }
            let models = AIModelListParser.parse(data, format: config.provider.preset.modelListFormat)
            return Result(models: models, error: models.isEmpty ? "No models returned" : nil)
        } catch {
            return Result(models: [], error: "Connection failed: \(error.localizedDescription)")
        }
    }

    private static func buildRequest(config: AIConfig, apiKey: String?) -> URLRequest? {
        let preset = config.provider.preset
        let urlString: String
        var headers: [(String, String)] = []

        switch preset.modelListFormat {
        case .anthropic:
            urlString = "https://api.anthropic.com/v1/models"
            headers = [
                ("x-api-key", apiKey ?? ""),
                ("anthropic-version", "2023-06-01"),
            ]
        case .ollamaTags:
            // Ollama's native tag listing lives outside the OpenAI-compatible /v1 path.
            urlString = trimSlash(config.localOllamaURL) + "/api/tags"
        case .openAI:
            urlString = preset.chatBaseURL(config: config) + "/models"
            if let key = apiKey, !key.isEmpty {
                headers = [("Authorization", "Bearer \(key)")]
            }
        }

        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        return request
    }

    private static func trimSlash(_ s: String) -> String {
        var out = s
        while out.hasSuffix("/") { out.removeLast() }
        return out
    }
}
