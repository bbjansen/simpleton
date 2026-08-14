// Sources/SimpletonSQL/SQLSavedQueryStore.swift
import Foundation

/// One user-named, reusable query. Unique by `name` within a connection — re-saving a name overwrites.
public struct SavedQuery: Codable, Sendable, Hashable {
    public var name: String
    public var sql: String
    public init(name: String, sql: String) {
        self.name = name
        self.sql = sql
    }
}

/// Per-connection saved/favorite queries, persisted to `sql-saved-queries.json` in the support dir.
/// Distinct from `SQLQueryHistoryStore` (which auto-records recents): these are explicit, named
/// favorites the user manages. Tolerant Codable so schema growth never drops existing saves.
public actor SQLSavedQueryStore {
    private let fileURL: URL
    private var byConnection: [String: [SavedQuery]] = [:]
    private var loaded = false

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("sql-saved-queries.json")
    }

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode(SavedFile.self, from: data)
        else { return }
        byConnection = decoded.byConnection
    }

    /// The saved queries for a connection, sorted by name (case-insensitive) for stable display.
    public func saved(for connectionID: UUID) -> [SavedQuery] {
        ensureLoaded()
        return byConnection[connectionID.uuidString] ?? []
    }

    /// Upsert a named query: an existing entry with the same (trimmed) name is replaced. Empty names
    /// or blank SQL are ignored. Keeps the list sorted by name so the menu order is stable.
    public func save(name: String, sql: String, for connectionID: UUID) {
        ensureLoaded()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSQL = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedSQL.isEmpty else { return }
        let key = connectionID.uuidString
        var list = byConnection[key] ?? []
        list.removeAll { $0.name == trimmedName }
        list.append(SavedQuery(name: trimmedName, sql: trimmedSQL))
        list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        byConnection[key] = list
        try? persist()
    }

    /// Remove the saved query with `name` (exact match) from a connection, if present.
    public func remove(name: String, for connectionID: UUID) {
        ensureLoaded()
        let key = connectionID.uuidString
        guard var list = byConnection[key] else { return }
        list.removeAll { $0.name == name }
        byConnection[key] = list
        try? persist()
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(SavedFile(byConnection: byConnection))
        try data.write(to: fileURL, options: .atomic)
    }

    private struct SavedFile: Codable {
        var version: Int = 1
        var byConnection: [String: [SavedQuery]] = [:]
        init(byConnection: [String: [SavedQuery]]) { self.byConnection = byConnection }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
            byConnection = try c.decodeIfPresent([String: [SavedQuery]].self, forKey: .byConnection) ?? [:]
        }
    }
}
