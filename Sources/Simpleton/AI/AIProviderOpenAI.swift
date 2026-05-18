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

    func completeWithTools(
        system: String, turns: [ConversationTurn], model: String, options: AIOptions
    ) async throws -> AgentTurnResult {
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }

        var messages: [[String: Any]] = [["role": "system", "content": system]]
        for turn in turns {
            switch turn.role {
            case .user(let text):
                messages.append(["role": "user", "content": text])
            case .assistant(let text):
                messages.append(["role": "assistant", "content": text])
            case .toolResult(let toolCallID, let output):
                messages.append(["role": "tool", "tool_call_id": toolCallID, "content": output])
            }
        }

        let tools: [[String: Any]] = [
            [
                "type": "function",
                "function": [
                    "name": "run_command",
                    "description": "Execute a shell command in a terminal pane and return its output. Use 'pane' to target a specific pane by number.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "cmd": ["type": "string", "description": "Shell command to execute"],
                            "explanation": ["type": "string", "description": "Brief reason this command is needed"],
                            "pane": ["type": "integer", "description": "Target pane number (1-based). Omit for focused pane."]
                        ] as [String: Any],
                        "required": ["cmd", "explanation"]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            [
                "type": "function",
                "function": [
                    "name": "read_pane_output",
                    "description": "Read recent terminal output from a pane without running a command.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "pane": ["type": "integer", "description": "Pane number (1-based). Omit for focused pane."],
                            "lines": ["type": "integer", "description": "Number of recent lines (default 50, max 200)"]
                        ] as [String: Any],
                        "required": [] as [String]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            [
                "type": "function",
                "function": [
                    "name": "list_panes",
                    "description": "List all terminal panes with their working directory, shell, and state.",
                    "parameters": ["type": "object", "properties": [:] as [String: Any], "required": [] as [String]] as [String: Any]
                ] as [String: Any]
            ],
            [
                "type": "function",
                "function": [
                    "name": "get_pane_state",
                    "description": "Get detailed state of a specific pane.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "pane": ["type": "integer", "description": "Pane number (1-based)"]
                        ] as [String: Any],
                        "required": ["pane"]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            [
                "type": "function",
                "function": [
                    "name": "read_file",
                    "description": "Read file contents (up to 10k chars). Use instead of cat.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "path": ["type": "string", "description": "File path (~ expansion supported)"]
                        ] as [String: Any],
                        "required": ["path"]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            [
                "type": "function",
                "function": [
                    "name": "write_file",
                    "description": "Write content to a file. Creates parent dirs if needed.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "path": ["type": "string", "description": "File path"],
                            "content": ["type": "string", "description": "Full file content"]
                        ] as [String: Any],
                        "required": ["path", "content"]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            [
                "type": "function",
                "function": [
                    "name": "list_directory",
                    "description": "List files and directories at a path with types and sizes.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "path": ["type": "string", "description": "Directory path (default: cwd). ~ supported."]
                        ] as [String: Any],
                        "required": [] as [String]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            [
                "type": "function",
                "function": [
                    "name": "search_files",
                    "description": "Recursive grep for a pattern across files.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "pattern": ["type": "string", "description": "Text or regex pattern"],
                            "directory": ["type": "string", "description": "Directory to search (default: cwd)"]
                        ] as [String: Any],
                        "required": ["pattern"]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            [
                "type": "function",
                "function": [
                    "name": "get_system_info",
                    "description": "Get OS, hostname, CPU, memory, uptime, user, shell.",
                    "parameters": ["type": "object", "properties": [:] as [String: Any], "required": [] as [String]] as [String: Any]
                ] as [String: Any]
            ],
            [
                "type": "function",
                "function": [
                    "name": "edit_file",
                    "description": "Replace specific text in a file. Safer than write_file for targeted changes.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "path": ["type": "string"],
                            "old_text": ["type": "string", "description": "Exact text to find"],
                            "new_text": ["type": "string", "description": "Replacement"],
                            "replace_all": ["type": "boolean", "description": "Replace all matches (default false)"]
                        ] as [String: Any],
                        "required": ["path", "old_text", "new_text"]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            [
                "type": "function",
                "function": [
                    "name": "get_git_status",
                    "description": "Git status (short format).",
                    "parameters": ["type": "object", "properties": ["directory": ["type": "string"]] as [String: Any], "required": [] as [String]] as [String: Any]
                ] as [String: Any]
            ],
            [
                "type": "function",
                "function": [
                    "name": "get_git_diff",
                    "description": "Git diff summary. staged=true for staged changes.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "directory": ["type": "string"],
                            "staged": ["type": "boolean"]
                        ] as [String: Any],
                        "required": [] as [String]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            [
                "type": "function",
                "function": [
                    "name": "get_git_log",
                    "description": "Recent git commits (oneline).",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "directory": ["type": "string"],
                            "count": ["type": "integer"]
                        ] as [String: Any],
                        "required": [] as [String]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            [
                "type": "function",
                "function": [
                    "name": "clipboard_copy",
                    "description": "Copy text to system clipboard.",
                    "parameters": [
                        "type": "object",
                        "properties": ["text": ["type": "string"]] as [String: Any],
                        "required": ["text"]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            [
                "type": "function",
                "function": [
                    "name": "send_keys",
                    "description": "Send keystrokes to a pane: ctrl+c, ctrl+d, enter, tab, escape, arrow keys, or raw text.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "keys": ["type": "string", "description": "Key name or raw text"],
                            "pane": ["type": "integer", "description": "Target pane (1-based)"]
                        ] as [String: Any],
                        "required": ["keys"]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            [
                "type": "function",
                "function": [
                    "name": "get_env",
                    "description": "Get environment variable(s). Omit name for all.",
                    "parameters": ["type": "object", "properties": ["name": ["type": "string"]] as [String: Any], "required": [] as [String]] as [String: Any]
                ] as [String: Any]
            ],
            [
                "type": "function",
                "function": [
                    "name": "http_request",
                    "description": "Make an HTTP request. Test APIs, check endpoints.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "url": ["type": "string"],
                            "method": ["type": "string", "description": "GET, POST, PUT, DELETE, etc."],
                            "headers": ["type": "object"],
                            "body": ["type": "string"]
                        ] as [String: Any],
                        "required": ["url"]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            [
                "type": "function",
                "function": [
                    "name": "check_port",
                    "description": "Check if a port is in use and what's using it.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "port": ["type": "integer"],
                            "host": ["type": "string"]
                        ] as [String: Any],
                        "required": ["port"]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            [
                "type": "function",
                "function": [
                    "name": "find_process",
                    "description": "Find processes by name.",
                    "parameters": ["type": "object", "properties": ["name": ["type": "string"]] as [String: Any], "required": ["name"]] as [String: Any]
                ] as [String: Any]
            ],
            [
                "type": "function",
                "function": [
                    "name": "kill_process",
                    "description": "Send signal to a process. Signals: TERM, KILL, INT, HUP.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "pid": ["type": "integer"],
                            "signal": ["type": "string"]
                        ] as [String: Any],
                        "required": ["pid"]
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ]

        let body: [String: Any] = [
            "model": model, "max_tokens": options.maxTokens,
            "temperature": options.temperature,
            "messages": messages, "tools": tools, "tool_choice": "auto"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.providerError("OpenAI tool use error: \(msg)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            throw AIError.invalidResponse
        }

        if let toolCalls = message["tool_calls"] as? [[String: Any]],
           let call = toolCalls.first,
           let toolID = call["id"] as? String,
           let function = call["function"] as? [String: Any],
           let toolName = function["name"] as? String,
           let argsStr = function["arguments"] as? String,
           let argsData = argsStr.data(using: .utf8),
           let args = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] {
            return .toolCall(id: toolID, name: toolName, arguments: args)
        }

        let content = message["content"] as? String ?? ""
        return .text(content.isEmpty ? "[No response]" : content)
    }
}
