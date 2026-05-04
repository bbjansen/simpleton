// Sources/SimpletonCore/Models/FrecencyEntry.swift
import Foundation

public struct FrecencyEntry: Codable, Equatable {
    public var score: Double
    public var lastUsed: Date
    public var useCount: Int
    public var recentTimestamps: [Date]

    public init(score: Double = 0, lastUsed: Date = Date(), useCount: Int = 0, recentTimestamps: [Date] = []) {
        self.score = score
        self.lastUsed = lastUsed
        self.useCount = useCount
        self.recentTimestamps = recentTimestamps
    }
}

public struct FrecencyFile: Codable {
    public let version: Int
    public var entries: [UUID: FrecencyEntry]

    public init(version: Int = 1, entries: [UUID: FrecencyEntry] = [:]) {
        self.version = version
        self.entries = entries
    }
}
