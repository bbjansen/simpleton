// Sources/Simpleton/AI/Tools/NetworkTools.swift
import Foundation

struct NetworkTools: ToolHandler {
    static let handledTools: Set<String> = [
        "http_request", "check_port",
    ]

    func handle(name: String, args: [String: Any], context: ToolContext) async -> String {
        switch name {
        case "http_request":
            return await handleHttpRequest(args)
        case "check_port":
            return await handleCheckPort(args, processRunner: context.processRunner)
        default:
            return "Unknown network tool: \(name)"
        }
    }

    private func handleHttpRequest(_ args: [String: Any]) async -> String {
        guard let urlStr = args["url"] as? String,
              let url = URL(string: urlStr) else {
            return "Missing or invalid 'url' parameter"
        }
        let method = (args["method"] as? String ?? "GET").uppercased()
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        if let headers = args["headers"] as? [String: String] {
            for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        }
        if let body = args["body"] as? String {
            request.httpBody = body.data(using: .utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            let status = httpResponse?.statusCode ?? 0
            let bodyStr = String(data: data, encoding: .utf8) ?? "[Binary data, \(data.count) bytes]"
            let maxChars = 5000
            let truncated = bodyStr.count > maxChars ? String(bodyStr.prefix(maxChars)) + "\n[... truncated]" : bodyStr
            return "HTTP \(status)\n\(truncated)"
        } catch {
            return "HTTP error: \(error.localizedDescription)"
        }
    }

    private func handleCheckPort(_ args: [String: Any], processRunner: ProcessRunner) async -> String {
        guard let port = args["port"] as? Int else {
            return "Missing 'port' parameter"
        }
        let host = args["host"] as? String ?? "localhost"
        let result = await processRunner.run("/usr/sbin/lsof", args: ["-i", ":\(port)", "-P", "-n"])
        if result.isEmpty {
            return "Port \(port) on \(host): not in use"
        } else {
            return "Port \(port) on \(host):\n\(result)"
        }
    }
}
