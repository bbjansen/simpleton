// Sources/SimpletonSQL/SQLQueryHistoryStore.swift
import Foundation

/// Per-connection query history, persisted to `sql-history.json` in the support dir (last 50 per
/// connection id). Tolerant Codable so schema growth never drops existing history.
public actor SQLQueryHistoryStore {
    private let fileURL: URL
    private var byConnection: [String: [String]] = [:]
    private var loaded = false
    private let maxPerConnection = 50

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("sql-history.json")
    }

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode(HistoryFile.self, from: data)
        else { return }
        byConnection = decoded.byConnection
    }

    public func history(for connectionID: UUID) -> [String] {
        ensureLoaded()
        return byConnection[connectionID.uuidString] ?? []
    }

    public func record(_ query: String, for connectionID: UUID) {
        ensureLoaded()
        let key = connectionID.uuidString
        var list = byConnection[key] ?? []
        list.removeAll { $0 == query }
        list.insert(query, at: 0)
        if list.count > maxPerConnection { list = Array(list.prefix(maxPerConnection)) }
        byConnection[key] = list
        try? save()
    }

    private func save() throws {
        let data = try JSONEncoder().encode(HistoryFile(byConnection: byConnection))
        try data.write(to: fileURL, options: .atomic)
    }

    private struct HistoryFile: Codable {
        var version: Int = 1
        var byConnection: [String: [String]] = [:]
        init(byConnection: [String: [String]]) { self.byConnection = byConnection }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
            byConnection = try c.decodeIfPresent([String: [String]].self, forKey: .byConnection) ?? [:]
        }
    }
}
