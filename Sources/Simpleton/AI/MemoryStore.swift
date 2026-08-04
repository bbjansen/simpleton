import CryptoKit
// Sources/Simpleton/AI/MemoryStore.swift
import Foundation
import NaturalLanguage

@MainActor
final class MemoryStore {
    private let storageDir: URL
    private var entries: [MemoryEntry] = []
    private let embeddingEngine = EmbeddingEngine()
    private var currentProjectHash: String?
    private let maxEntries = 100
    private let pruneAgeDays = 90
    private let minUseCountForRetention = 2

    init(storageDir: URL) {
        self.storageDir = storageDir
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
    }

    // MARK: - Project Scoping

    static func projectHash(for path: String) -> String {
        let normalized = (path as NSString).standardizingPath
        let data = Data(normalized.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private func storageURL(for projectHash: String) -> URL {
        storageDir.appendingPathComponent("\(projectHash).json")
    }

    // MARK: - Load / Save

    func loadForProject(path: String) {
        let hash = Self.projectHash(for: path)
        currentProjectHash = hash
        let url = storageURL(for: hash)

        guard FileManager.default.fileExists(atPath: url.path) else {
            entries = []
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([MemoryEntry].self, from: data)
            prune()
        } catch {
            print("[MemoryStore] Failed to load: \(error)")
            entries = []
        }
    }

    func save() {
        guard let hash = currentProjectHash else { return }
        let url = storageURL(for: hash)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[MemoryStore] Failed to save: \(error)")
        }
    }

    // MARK: - CRUD

    func addMemory(content: String, type: MemoryEntry.MemoryType, tags: [String]) -> MemoryEntry? {
        let vector = embeddingEngine.embed(content) ?? []
        let entry = MemoryEntry(type: type, content: content, tags: tags, embedding: vector)
        entries.append(entry)
        enforceLimit()
        save()
        return entry
    }

    func deleteMemory(id: UUID) -> Bool {
        let count = entries.count
        entries.removeAll { $0.id == id }
        if entries.count != count {
            save()
            return true
        }
        return false
    }

    func allMemories(type: MemoryEntry.MemoryType? = nil) -> [MemoryEntry] {
        if let type = type {
            return entries.filter { $0.type == type }
        }
        return entries
    }

    // MARK: - Semantic Search

    func query(_ text: String, topK: Int = 5, threshold: Float = 0.3) -> [MemoryEntry] {
        guard let queryVector = embeddingEngine.embed(text) else {
            return substringSearch(text, topK: topK)
        }

        var scored: [(entry: MemoryEntry, score: Float)] = []
        var updatedIDs: Set<UUID> = []
        for entry in entries {
            if entry.embedding.isEmpty {
                let textMatch =
                    entry.content.localizedCaseInsensitiveContains(text)
                    || entry.tags.contains(where: { $0.localizedCaseInsensitiveContains(text) })
                if textMatch {
                    scored.append((entry, 0.31))
                    updatedIDs.insert(entry.id)
                }
                continue
            }
            let sim = EmbeddingEngine.cosineSimilarity(queryVector, entry.embedding)
            if sim >= threshold {
                scored.append((entry, sim))
                updatedIDs.insert(entry.id)
            }
        }

        // Apply usage updates after iteration completes
        let now = Date()
        for id in updatedIDs {
            if let idx = entries.firstIndex(where: { $0.id == id }) {
                entries[idx].lastUsed = now
                entries[idx].useCount += 1
            }
        }

        scored.sort { $0.score > $1.score }
        let results = Array(scored.prefix(topK).map(\.entry))
        if !results.isEmpty { save() }
        return results
    }

    func relevantMemories(forContext context: String, topK: Int = 10) -> [MemoryEntry] {
        return query(context, topK: topK, threshold: 0.25)
    }

    // MARK: - Fallback Search

    private func substringSearch(_ text: String, topK: Int) -> [MemoryEntry] {
        let words = text.lowercased().split(separator: " ").map(String.init)
        var scored: [(entry: MemoryEntry, matchCount: Int)] = []

        for entry in entries {
            let searchable = (entry.content + " " + entry.tags.joined(separator: " ")).lowercased()
            let matchCount = words.filter { searchable.contains($0) }.count
            if matchCount > 0 {
                scored.append((entry, matchCount))
            }
        }

        scored.sort { $0.matchCount > $1.matchCount }
        return Array(scored.prefix(topK).map(\.entry))
    }

    // MARK: - Pruning

    private func prune() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -pruneAgeDays, to: Date()) ?? Date()
        entries.removeAll { entry in
            entry.lastUsed < cutoff && entry.useCount < minUseCountForRetention
        }
    }

    private func enforceLimit() {
        guard entries.count > maxEntries else { return }
        entries.sort { a, b in
            if a.useCount != b.useCount { return a.useCount > b.useCount }
            return a.lastUsed > b.lastUsed
        }
        entries = Array(entries.prefix(maxEntries))
    }
}

// MARK: - Embedding Engine

struct EmbeddingEngine {
    private let embedding: NLEmbedding?

    init() {
        embedding = NLEmbedding.sentenceEmbedding(for: .english)
    }

    func embed(_ text: String) -> [Float]? {
        guard let embedding else { return nil }
        guard let vector = embedding.vector(for: text) else { return nil }
        return vector.map { Float($0) }
    }

    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, normA: Float = 0, normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }
}
