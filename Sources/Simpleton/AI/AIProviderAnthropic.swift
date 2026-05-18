// Sources/Simpleton/AI/AIProviderAnthropic.swift
import Foundation

/// Anthropic Messages API provider.
struct AnthropicProvider: AIProviderProtocol {

    let apiKey: String

    func complete(system: String, user: String, model: String, options: AIOptions) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": options.maxTokens,
            "temperature": options.temperature,
            "system": system,
            "messages": [["role": "user", "content": user]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else { throw AIError.invalidResponse }
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.providerError("Anthropic API error (\(httpResponse.statusCode)): \(errorBody)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw AIError.invalidResponse
        }
        return text
    }

    func stream(system: String, user: String, model: String, options: AIOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = URL(string: "https://api.anthropic.com/v1/messages")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

                    let body: [String: Any] = [
                        "model": model,
                        "max_tokens": options.maxTokens,
                        "temperature": options.temperature,
                        "system": system,
                        "stream": true,
                        "messages": [["role": "user", "content": user]]
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        throw AIError.providerError("Anthropic streaming failed")
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = String(line.dropFirst(6))
                        guard jsonStr != "[DONE]",
                              let data = jsonStr.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                        if let delta = event["delta"] as? [String: Any],
                           let text = delta["text"] as? String {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func completeWithTools(
        system: String, turns: [ConversationTurn], model: String, options: AIOptions
    ) async throws -> AgentTurnResult {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var messages: [[String: Any]] = []
        for turn in turns {
            switch turn.role {
            case .user(let text):
                messages.append(["role": "user", "content": text])
            case .assistant(let text):
                messages.append(["role": "assistant", "content": text])
            case .toolResult(let toolCallID, let output):
                messages.append([
                    "role": "user",
                    "content": [["type": "tool_result", "tool_use_id": toolCallID, "content": output]]
                ])
            }
        }

        let tools: [[String: Any]] = [[
            "name": "run_command",
            "description": "Execute a shell command in the terminal and observe its output",
            "input_schema": [
                "type": "object",
                "properties": [
                    "cmd": ["type": "string", "description": "Shell command to execute"],
                    "explanation": ["type": "string", "description": "Why this command is needed"]
                ] as [String: Any],
                "required": ["cmd", "explanation"]
            ] as [String: Any]
        ]]

        let body: [String: Any] = [
            "model": model, "max_tokens": options.maxTokens,
            "temperature": options.temperature,
            "system": system, "messages": messages, "tools": tools
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.providerError("Anthropic tool use error: \(msg)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw AIError.invalidResponse
        }

        if let block = content.first(where: { $0["type"] as? String == "tool_use" }),
           let toolID = block["id"] as? String,
           let input = block["input"] as? [String: Any],
           let cmd = input["cmd"] as? String {
            let explanation = input["explanation"] as? String ?? ""
            return .toolCall(id: toolID, cmd: cmd, explanation: explanation)
        }

        let text = content.compactMap { $0["text"] as? String }.joined()
        return .text(text.isEmpty ? "[No response]" : text)
    }
}
