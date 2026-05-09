// Sources/Simpleton/AI/AIProviderOpenAI.swift
import Foundation

/// OpenAI Chat Completions API provider. Also used for Ollama and custom endpoints.
struct OpenAIProvider: AIProviderProtocol {

    let apiKey: String
    let baseURL: String

    func complete(system: String, user: String, model: String, options: AIOptions) async throws -> String {
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": options.maxTokens,
            "temperature": options.temperature,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else { throw AIError.invalidResponse }
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.providerError("API error (\(httpResponse.statusCode)): \(errorBody)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            throw AIError.invalidResponse
        }
        // Some models (e.g. Qwen) put thinking in "reasoning" and answer in "content"
        let content = message["content"] as? String ?? ""
        let reasoning = message["reasoning"] as? String
        if content.isEmpty, let reasoning = reasoning {
            return reasoning
        }
        guard !content.isEmpty else { throw AIError.invalidResponse }
        return content
    }

    func stream(system: String, user: String, model: String, options: AIOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = URL(string: "\(baseURL)/chat/completions")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if !apiKey.isEmpty {
                        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    }

                    let body: [String: Any] = [
                        "model": model,
                        "max_tokens": options.maxTokens,
                        "temperature": options.temperature,
                        "stream": true,
                        "messages": [
                            ["role": "system", "content": system],
                            ["role": "user", "content": user]
                        ]
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AIError.providerError("No response from server")
                    }
                    guard httpResponse.statusCode == 200 else {
                        // Try to read error body for better message
                        var errorMsg = "Streaming failed (\(httpResponse.statusCode))"
                        var bodyData = Data()
                        for try await byte in bytes { bodyData.append(byte); if bodyData.count > 500 { break } }
                        if let body = String(data: bodyData, encoding: .utf8), body.contains("not found") {
                            errorMsg = "Model '\(model)' not found. Check Preferences > AI > Model name."
                        }
                        throw AIError.providerError(errorMsg)
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = String(line.dropFirst(6))
                        guard jsonStr != "[DONE]",
                              let data = jsonStr.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                        if let choices = event["choices"] as? [[String: Any]],
                           let delta = choices.first?["delta"] as? [String: Any] {
                            // Check both "content" and "reasoning" (Qwen-style thinking models)
                            if let content = delta["content"] as? String, !content.isEmpty {
                                continuation.yield(content)
                            } else if let reasoning = delta["reasoning"] as? String, !reasoning.isEmpty {
                                continuation.yield(reasoning)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
