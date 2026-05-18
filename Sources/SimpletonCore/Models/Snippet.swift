// Sources/SimpletonCore/Models/Snippet.swift
import Foundation

public struct Snippet: Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var command: String     // may contain {placeholder} tokens
    public var tags: [String]

    public init(id: UUID = UUID(), name: String, command: String, tags: [String] = []) {
        self.id = id
        self.name = name
        self.command = command
        self.tags = tags
    }
}
