// Sources/Simpleton/AI/MCP/MCPConfig.swift
import Foundation

struct MCPServerConfig: Codable, Identifiable {
    let id: UUID
    var name: String
    var command: String
    var args: [String]
    var env: [String: String]
    var enabled: Bool

    init(
        id: UUID = UUID(), name: String, command: String, args: [String] = [],
        env: [String: String] = [:], enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.args = args
        self.env = env
        self.enabled = enabled
    }
}

final class MCPConfigStore {
    private let fileURL: URL
    private(set) var servers: [MCPServerConfig] = []

    init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("mcp-servers.json")
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            servers = try JSONDecoder().decode([MCPServerConfig].self, from: data)
        } catch {
            print("[MCP] Failed to load config: \(error)")
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(servers)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[MCP] Failed to save config: \(error)")
        }
    }

    func add(_ config: MCPServerConfig) {
        servers.append(config)
        save()
    }

    func update(_ config: MCPServerConfig) {
        if let idx = servers.firstIndex(where: { $0.id == config.id }) {
            servers[idx] = config
            save()
        }
    }

    func delete(id: UUID) {
        servers.removeAll { $0.id == id }
        save()
    }

    var enabledServers: [MCPServerConfig] {
        servers.filter(\.enabled)
    }
}
