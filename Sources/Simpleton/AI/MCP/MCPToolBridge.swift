// Sources/Simpleton/AI/MCP/MCPToolBridge.swift
import Foundation
import SimpletonCore

/// Adapts MCP server tools to the ToolHandler protocol so they integrate
/// seamlessly with the AI agent's tool registry.
///
/// Tool names are prefixed with the server config name (lowercased, spaces
/// replaced with dashes) to prevent collisions: `github.list_repos`.
struct MCPToolBridge: ToolHandler {

    private let clients: [MCPClient]

    init(clients: [MCPClient]) {
        self.clients = clients
    }

    // MARK: - ToolHandler

    static var handledTools: Set<String> {
        // Static property cannot access instance state; return empty.
        // The actual tools are registered dynamically via `allToolNames`.
        []
    }

    /// The dynamic set of tool names from all connected clients.
    var allToolNames: Set<String> {
        var names = Set<String>()
        for client in clients where client.isConnected {
            let prefix = Self.prefix(for: client.config)
            for tool in client.tools {
                names.insert("\(prefix).\(tool.name)")
            }
        }
        return names
    }

    func handle(name: String, args: [String: Any], context: ToolContext) async -> String {
        // Parse "prefix.toolName" format
        guard let dotIndex = name.firstIndex(of: ".") else {
            return "Error: invalid MCP tool name '\(name)' — expected 'server.tool' format"
        }
        let prefix = String(name[name.startIndex..<dotIndex])
        let toolName = String(name[name.index(after: dotIndex)...])

        // Find the client that owns this tool
        guard let client = clients.first(where: {
            $0.isConnected && Self.prefix(for: $0.config) == prefix
        }) else {
            return "Error: MCP server '\(prefix)' is not connected"
        }

        do {
            return try await client.callTool(name: toolName, arguments: args)
        } catch {
            return "Error calling MCP tool '\(name)': \(error.localizedDescription)"
        }
    }

    /// Build tool descriptions for the system prompt.
    func toolDescriptions() -> String {
        var sections: [String] = []
        for client in clients where client.isConnected {
            let prefix = Self.prefix(for: client.config)
            let toolLines = client.tools.map { tool in
                let params = formatInputSchema(tool.inputSchema)
                return "  - **\(prefix).\(tool.name)**\(params): \(tool.description)"
            }
            if !toolLines.isEmpty {
                sections.append("MCP: \(client.config.name)\n\(toolLines.joined(separator: "\n"))")
            }
        }
        return sections.joined(separator: "\n\n")
    }

    // MARK: - Helpers

    static func prefix(for config: MCPServerConfig) -> String {
        config.name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }

    /// Format an inputSchema into a brief parameter hint like `(owner, repo)`.
    private func formatInputSchema(_ schema: [String: Any]) -> String {
        guard let properties = schema["properties"] as? [String: Any] else { return "" }
        let names = properties.keys.sorted()
        guard !names.isEmpty else { return "" }
        return "(\(names.joined(separator: ", ")))"
    }
}
