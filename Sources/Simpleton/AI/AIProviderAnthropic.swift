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

        let tools: [[String: Any]] = [
            [
                "name": "run_command",
                "description": "Execute a shell command in a terminal pane and return its output. Use the 'pane' parameter to target a specific pane by number (1-based). Omit 'pane' to run on the focused pane.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "cmd": ["type": "string", "description": "Shell command to execute"],
                        "explanation": ["type": "string", "description": "Brief reason this command is needed"],
                        "pane": ["type": "integer", "description": "Target pane number (1-based). Omit for focused pane."]
                    ] as [String: Any],
                    "required": ["cmd", "explanation"]
                ] as [String: Any]
            ],
            [
                "name": "read_pane_output",
                "description": "Read the recent terminal output from a pane without running any command. Use this to check what happened, see error messages, or monitor a running process.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "pane": ["type": "integer", "description": "Pane number (1-based). Omit for focused pane."],
                        "lines": ["type": "integer", "description": "Number of recent lines to read (default 50, max 200)"]
                    ] as [String: Any],
                    "required": [] as [String]
                ] as [String: Any]
            ],
            [
                "name": "list_panes",
                "description": "List all terminal panes in the current tab with their working directory, shell, and running state. Use this to understand the workspace before acting.",
                "input_schema": [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ] as [String: Any]
            ],
            [
                "name": "get_pane_state",
                "description": "Get detailed state of a specific pane: working directory, shell, connection type, and recent output.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "pane": ["type": "integer", "description": "Pane number (1-based)"]
                    ] as [String: Any],
                    "required": ["pane"]
                ] as [String: Any]
            ],
            [
                "name": "read_file",
                "description": "Read the contents of a file. Returns up to 10,000 characters. Use this instead of cat to avoid shell quoting issues.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "Absolute or relative file path (~ expansion supported)"]
                    ] as [String: Any],
                    "required": ["path"]
                ] as [String: Any]
            ],
            [
                "name": "write_file",
                "description": "Write content to a file. Creates parent directories if needed. Use this instead of echo/heredoc to avoid shell escaping issues.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "Absolute or relative file path"],
                        "content": ["type": "string", "description": "The full file content to write"]
                    ] as [String: Any],
                    "required": ["path", "content"]
                ] as [String: Any]
            ],
            [
                "name": "list_directory",
                "description": "List files and directories at a path. Returns names, types (file/dir), and sizes.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "Directory path (default: current directory). ~ expansion supported."]
                    ] as [String: Any],
                    "required": [] as [String]
                ] as [String: Any]
            ],
            [
                "name": "search_files",
                "description": "Search for a text pattern across files in a directory (recursive grep). Returns matching file paths.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "pattern": ["type": "string", "description": "Text or regex pattern to search for"],
                        "directory": ["type": "string", "description": "Directory to search in (default: current directory)"]
                    ] as [String: Any],
                    "required": ["pattern"]
                ] as [String: Any]
            ],
            [
                "name": "get_system_info",
                "description": "Get system information: OS version, hostname, CPU cores, memory, uptime, current user, shell.",
                "input_schema": [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ] as [String: Any]
            ]
        ]

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
           let toolName = block["name"] as? String,
           let input = block["input"] as? [String: Any] {
            return .toolCall(id: toolID, name: toolName, arguments: input)
        }

        let text = content.compactMap { $0["text"] as? String }.joined()
        return .text(text.isEmpty ? "[No response]" : text)
    }
}
