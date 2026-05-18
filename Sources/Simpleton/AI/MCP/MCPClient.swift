// Sources/Simpleton/AI/MCP/MCPClient.swift
import Foundation

final class MCPClient {
    let config: MCPServerConfig
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var requestID: Int = 0
    private(set) var tools: [MCPTool] = []
    private(set) var isConnected = false

    /// Serial queue protecting requestID, readBuffer, and pipe I/O.
    private let ioQueue = DispatchQueue(label: "simpleton.mcp.io")

    /// Buffer for partial lines read from stdout.
    private var readBuffer = Data()

    struct MCPTool {
        let name: String
        let description: String
        let inputSchema: [String: Any]
    }

    init(config: MCPServerConfig) {
        self.config = config
    }

    // MARK: - Connect

    func connect() async throws {
        let proc = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        let resolved = resolveCommand(config.command)
        if resolved == "/usr/bin/env" && !config.command.hasPrefix("/") {
            // Command not found in PATH; use /usr/bin/env to resolve at runtime
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = [config.command] + config.args
        } else {
            proc.executableURL = URL(fileURLWithPath: resolved)
            proc.arguments = config.args
        }

        var env = ProcessInfo.processInfo.environment
        for (key, value) in config.env {
            env[key] = value
        }
        // Ensure PATH includes common tool locations for npx, uvx, etc.
        let extraPaths = ["/usr/local/bin", "/opt/homebrew/bin"]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
        proc.environment = env
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        stdinHandle = stdinPipe.fileHandleForWriting
        stdoutHandle = stdoutPipe.fileHandleForReading

        do {
            try proc.run()
        } catch {
            throw MCPError.launchFailed(config.name, error.localizedDescription)
        }
        process = proc

        // 1. Send initialize
        let initResult = try await sendRequest(method: "initialize", params: [
            "protocolVersion": "2024-11-05",
            "capabilities": [String: Any](),
            "clientInfo": [
                "name": "Simpleton",
                "version": "1.0.0"
            ]
        ])

        guard initResult["protocolVersion"] != nil else {
            disconnect()
            throw MCPError.initFailed(config.name, "Server did not return protocolVersion")
        }

        // 2. Send initialized notification (no id — it's a notification)
        sendNotification(method: "notifications/initialized", params: [:])

        // 3. Discover tools
        let toolsResult = try await sendRequest(method: "tools/list", params: [:])
        if let toolList = toolsResult["tools"] as? [[String: Any]] {
            tools = toolList.compactMap { dict in
                guard let name = dict["name"] as? String else { return nil }
                let desc = dict["description"] as? String ?? ""
                let schema = dict["inputSchema"] as? [String: Any] ?? [:]
                return MCPTool(name: name, description: desc, inputSchema: schema)
            }
        }

        isConnected = true
        print("[MCP] Connected to \(config.name) — \(tools.count) tools discovered")
    }

    // MARK: - Call Tool

    func callTool(name: String, arguments: [String: Any]) async throws -> String {
        guard isConnected else {
            throw MCPError.notConnected(config.name)
        }

        let result = try await sendRequest(method: "tools/call", params: [
            "name": name,
            "arguments": arguments
        ], timeout: 10.0)

        // MCP tool results have a "content" array with text blocks
        if let content = result["content"] as? [[String: Any]] {
            let texts = content.compactMap { block -> String? in
                guard let type = block["type"] as? String, type == "text" else { return nil }
                return block["text"] as? String
            }
            return texts.joined(separator: "\n")
        }

        // Fallback: return the raw result as JSON string
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.fragmentsAllowed]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }

        return "(empty result)"
    }

    // MARK: - Disconnect

    func disconnect() {
        isConnected = false
        tools = []
        stdinHandle?.closeFile()
        stdinHandle = nil
        stdoutHandle?.closeFile()
        stdoutHandle = nil
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        process = nil
        ioQueue.sync { readBuffer = Data() }
        print("[MCP] Disconnected from \(config.name)")
    }

    // MARK: - JSON-RPC Transport

    private func sendRequest(method: String, params: [String: Any], timeout: TimeInterval = 10.0) async throws -> [String: Any] {
        let id: Int = ioQueue.sync {
            requestID += 1
            return requestID
        }

        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ]

        try ioQueue.sync { try writeMessage(message) }

        // Read responses until we get one matching our request ID
        return try await withThrowingTaskGroup(of: [String: Any].self) { group in
            group.addTask {
                try await self.waitForResponse(id: id)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw MCPError.timeout(self.config.name, method)
            }
            guard let result = try await group.next() else {
                throw MCPError.timeout(config.name, method)
            }
            group.cancelAll()
            return result
        }
    }

    private func sendNotification(method: String, params: [String: Any]) {
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ]
        ioQueue.sync { try? writeMessage(message) }
    }

    private func writeMessage(_ message: [String: Any]) throws {
        guard let handle = stdinHandle else {
            throw MCPError.notConnected(config.name)
        }
        let data = try JSONSerialization.data(withJSONObject: message, options: [])
        var payload = data
        payload.append(contentsOf: [0x0A]) // newline delimiter
        handle.write(payload)
    }

    private func waitForResponse(id: Int) async throws -> [String: Any] {
        while true {
            try Task.checkCancellation()

            if let line = ioQueue.sync(execute: { readLine() }) {
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue // skip malformed lines
                }

                // Check if this is a response to our request
                if let responseID = json["id"] as? Int, responseID == id {
                    if let error = json["error"] as? [String: Any] {
                        let message = error["message"] as? String ?? "Unknown error"
                        let code = error["code"] as? Int ?? -1
                        throw MCPError.serverError(config.name, code, message)
                    }
                    if let result = json["result"] as? [String: Any] {
                        return result
                    }
                    return [:]
                }
                // Not our response — could be a notification; skip it
            } else {
                // No complete line available yet, yield and retry
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
        }
    }

    /// Read one newline-delimited line from stdout, or nil if no complete line is available yet.
    private func readLine() -> String? {
        guard let handle = stdoutHandle else { return nil }

        // Read any available data into the buffer
        let chunk = handle.availableData
        if !chunk.isEmpty {
            readBuffer.append(chunk)
        }

        // Look for a newline in the buffer
        guard let newlineIndex = readBuffer.firstIndex(of: 0x0A) else {
            return nil
        }

        let lineData = readBuffer[readBuffer.startIndex..<newlineIndex]
        readBuffer = Data(readBuffer[(newlineIndex + 1)...])
        return String(data: lineData, encoding: .utf8)
    }

    // MARK: - Helpers

    /// Resolve a command name to an absolute path if it's not already one.
    private func resolveCommand(_ command: String) -> String {
        if command.hasPrefix("/") { return command }
        // Search PATH for the command
        let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")
            .split(separator: ":").map(String.init)
        let extraDirs = ["/usr/local/bin", "/opt/homebrew/bin"]
        for dir in (extraDirs + pathDirs) {
            let full = (dir as NSString).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: full) {
                return full
            }
        }
        // Fall back to /usr/bin/env to let the shell resolve it
        return "/usr/bin/env"
    }
}

// MARK: - Errors

enum MCPError: LocalizedError {
    case launchFailed(String, String)
    case initFailed(String, String)
    case notConnected(String)
    case timeout(String, String)
    case serverError(String, Int, String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let name, let reason):
            return "MCP server '\(name)' failed to launch: \(reason)"
        case .initFailed(let name, let reason):
            return "MCP server '\(name)' initialization failed: \(reason)"
        case .notConnected(let name):
            return "MCP server '\(name)' is not connected"
        case .timeout(let name, let method):
            return "MCP server '\(name)' timed out on '\(method)'"
        case .serverError(let name, let code, let message):
            return "MCP server '\(name)' error (\(code)): \(message)"
        }
    }
}
