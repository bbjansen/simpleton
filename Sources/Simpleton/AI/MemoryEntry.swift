// Sources/Simpleton/AI/MemoryEntry.swift
import Foundation

struct MemoryEntry: Codable, Identifiable {
    let id: UUID
    var type: MemoryType
    var content: String
    var tags: [String]
    var embedding: [Float]
    var createdAt: Date
    var lastUsed: Date
    var useCount: Int

    enum MemoryType: String, Codable, CaseIterable {
        case errorFix
        case convention
        case decision
        case environment
        case preference
    }

    init(id: UUID = UUID(), type: MemoryType, content: String, tags: [String], embedding: [Float], createdAt: Date = Date(), lastUsed: Date = Date(), useCount: Int = 0) {
        self.id = id
        self.type = type
        self.content = content
        self.tags = tags
        self.embedding = embedding
        self.createdAt = createdAt
        self.lastUsed = lastUsed
        self.useCount = useCount
    }

    var promptSummary: String {
        let tagStr = tags.isEmpty ? "" : " [\(tags.joined(separator: ", "))]"
        return "[\(type.rawValue)]\(tagStr) \(content)"
    }
}
