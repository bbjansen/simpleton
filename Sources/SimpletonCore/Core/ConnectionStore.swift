// Sources/SimpletonCore/Core/ConnectionStore.swift
import Foundation

extension Notification.Name {
    /// Posted on the main queue after connections change, so UI can refresh.
    public static let simpletonConnectionsChanged = Notification.Name("simpletonConnectionsChanged")
}

/// Persistent, actor-isolated store of `Connection`s, saved as JSON to `connections.json` in the
/// support directory. Mirrors `BookmarkStore` but for the generic client-viewer connections; the two
/// are independent. Secrets are not stored here (see `CredentialStore`).
public actor ConnectionStore {

    private let directory: URL
    private var connections: [UUID: Connection] = [:]
    private var loaded = false

    public init(directory: URL) {
        self.directory = directory
    }

    nonisolated private func postConnectionsChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .simpletonConnectionsChanged, object: nil)
        }
    }

    public func load() throws {
        let file = directory.appendingPathComponent("connections.json")
        if FileManager.default.fileExists(atPath: file.path) {
            let decoded = try AtomicFileWriter.readJSON(ConnectionFile.self, from: file)
            connections = Dictionary(uniqueKeysWithValues: decoded.connections.map { ($0.id, $0) })
        }
        loaded = true
    }

    private func ensureLoaded() throws {
        if !loaded { try load() }
    }

    public func add(_ connection: Connection) throws {
        try ensureLoaded()
        connections[connection.id] = connection
        try save()
        postConnectionsChanged()
    }

    public func update(_ connection: Connection) throws {
        try ensureLoaded()
        guard connections[connection.id] != nil else { return }
        var updated = connection
        updated.updatedAt = Date()
        connections[connection.id] = updated
        try save()
        postConnectionsChanged()
    }

    public func delete(id: UUID) throws {
        try ensureLoaded()
        connections.removeValue(forKey: id)
        try save()
        postConnectionsChanged()
    }

    public func all() -> [Connection] {
        try? ensureLoaded()
        return Array(connections.values).sorted { $0.name < $1.name }
    }

    public func byKind(_ kind: ConnectionKind) -> [Connection] {
        try? ensureLoaded()
        return connections.values.filter { $0.kind == kind }.sorted { $0.name < $1.name }
    }

    public func pinned() -> [Connection] {
        try? ensureLoaded()
        return connections.values.filter(\.pinned).sorted { $0.name < $1.name }
    }

    public func connection(for id: UUID) -> Connection? {
        try? ensureLoaded()
        return connections[id]
    }

    public func search(query: String) -> [Connection] {
        try? ensureLoaded()
        let q = query.lowercased()
        guard !q.isEmpty else { return all() }
        return connections.values
            .filter {
                $0.name.lowercased().contains(q)
                    || ($0.host?.lowercased().contains(q) ?? false)
                    || $0.tags.contains { $0.lowercased().contains(q) }
            }
            .sorted { $0.name < $1.name }
    }

    public func flush() throws {
        try save()
    }

    private func save() throws {
        let file = ConnectionFile(connections: Array(connections.values))
        try AtomicFileWriter.writeJSON(file, to: directory.appendingPathComponent("connections.json"))
    }
}

/// On-disk envelope for connections.json (versioned for forward migration).
public struct ConnectionFile: Codable {
    public let version: Int
    public var connections: [Connection]

    public init(version: Int = 1, connections: [Connection]) {
        self.version = version
        self.connections = connections
    }
}
