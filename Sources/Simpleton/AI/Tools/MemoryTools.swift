// Sources/Simpleton/AI/Tools/MemoryTools.swift
import Foundation

struct MemoryTools: ToolHandler {
    static let handledTools: Set<String> = [
        "save_memory", "recall_memory", "list_memories", "forget_memory",
    ]

    func handle(name: String, args: [String: Any], context: ToolContext) async -> String {
        guard let store = context.memoryStore else {
            return "Memory system not available"
        }

        switch name {
        case "save_memory":
            return handleSaveMemory(args, store: store)
        case "recall_memory":
            return handleRecallMemory(args, store: store)
        case "list_memories":
            return handleListMemories(args, store: store)
        case "forget_memory":
            return handleForgetMemory(args, store: store)
        default:
            return "Unknown memory tool: \(name)"
        }
    }

    private func handleSaveMemory(_ args: [String: Any], store: MemoryStore) -> String {
        guard let content = args["content"] as? String, !content.isEmpty else {
            return "Missing 'content' parameter"
        }
        let typeStr = args["type"] as? String ?? "convention"
        guard let type = MemoryEntry.MemoryType(rawValue: typeStr) else {
            let valid = MemoryEntry.MemoryType.allCases.map(\.rawValue).joined(separator: ", ")
            return "Invalid memory type '\(typeStr)'. Valid types: \(valid)"
        }
        let tags: [String]
        if let tagsArray = args["tags"] as? [String] {
            tags = tagsArray
        } else if let tagsStr = args["tags"] as? String {
            tags = tagsStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        } else {
            tags = []
        }

        if let entry = store.addMemory(content: content, type: type, tags: tags) {
            return "Memory saved (id: \(entry.id.uuidString.prefix(8)), type: \(type.rawValue), tags: \(tags.joined(separator: ", ")))"
        } else {
            return "Failed to save memory"
        }
    }

    private func handleRecallMemory(_ args: [String: Any], store: MemoryStore) -> String {
        guard let query = args["query"] as? String, !query.isEmpty else {
            return "Missing 'query' parameter"
        }
        let topK = args["count"] as? Int ?? 5
        let results = store.query(query, topK: topK)

        if results.isEmpty {
            return "No relevant memories found for: \(query)"
        }

        var output = "Found \(results.count) relevant memories:\n\n"
        for (index, entry) in results.enumerated() {
            let tagsStr = entry.tags.isEmpty ? "" : " [tags: \(entry.tags.joined(separator: ", "))]"
            let dateStr = formatDate(entry.createdAt)
            output += "\(index + 1). [\(entry.type.rawValue)]\(tagsStr)\n"
            output += "   \(entry.content)\n"
            output += "   (id: \(entry.id.uuidString.prefix(8)), saved: \(dateStr), used: \(entry.useCount)x)\n\n"
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleListMemories(_ args: [String: Any], store: MemoryStore) -> String {
        let typeFilter: MemoryEntry.MemoryType?
        if let typeStr = args["type"] as? String {
            typeFilter = MemoryEntry.MemoryType(rawValue: typeStr)
        } else {
            typeFilter = nil
        }

        let memories = store.allMemories(type: typeFilter)

        if memories.isEmpty {
            let filterStr = typeFilter.map { " of type '\($0.rawValue)'" } ?? ""
            return "No memories\(filterStr) stored for this project"
        }

        var output = "Memories (\(memories.count) total"
        if let type = typeFilter { output += ", filtered by '\(type.rawValue)'" }
        output += "):\n\n"

        for (index, entry) in memories.enumerated() {
            let tagsStr = entry.tags.isEmpty ? "" : " [tags: \(entry.tags.joined(separator: ", "))]"
            let dateStr = formatDate(entry.createdAt)
            output += "\(index + 1). [\(entry.type.rawValue)]\(tagsStr) \(entry.content)\n"
            output += "   (id: \(entry.id.uuidString.prefix(8)), saved: \(dateStr), used: \(entry.useCount)x)\n"
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleForgetMemory(_ args: [String: Any], store: MemoryStore) -> String {
        guard let idStr = args["id"] as? String else {
            return "Missing 'id' parameter"
        }

        let allMemories = store.allMemories()
        let match = allMemories.first { entry in
            entry.id.uuidString == idStr ||
            entry.id.uuidString.lowercased().hasPrefix(idStr.lowercased())
        }

        guard let entry = match else {
            return "Memory not found with id: \(idStr)"
        }

        if store.deleteMemory(id: entry.id) {
            return "Memory deleted (id: \(entry.id.uuidString.prefix(8)), content: '\(String(entry.content.prefix(50)))...')"
        } else {
            return "Failed to delete memory"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
