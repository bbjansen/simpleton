// Tests/CoreChecks/FrecencyEntryChecks.swift
// Ported from Tests/SimpletonCoreTests/Models/FrecencyEntryTests.swift
import Foundation
import SimpletonCore

func runFrecencyEntryChecks(_ t: TestRunner) {
    t.suite("FrecencyEntry.testFrecencyEntryRoundTrip") {
        do {
            let entry = FrecencyEntry(
                score: 245.8,
                lastUsed: Date(),
                useCount: 47,
                recentTimestamps: [Date(), Date().addingTimeInterval(-3600)]
            )
            let data = try JSONEncoder().encode(entry)
            let decoded = try JSONDecoder().decode(FrecencyEntry.self, from: data)
            t.expectEqual(decoded.useCount, 47, "useCount")
            t.expectEqual(decoded.recentTimestamps.count, 2, "recentTimestamps count")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    t.suite("FrecencyEntry.testFrecencyFileRoundTrip") {
        do {
            let id = UUID()
            let file = FrecencyFile(entries: [id: FrecencyEntry(score: 100, lastUsed: Date(), useCount: 5, recentTimestamps: [])])
            let data = try JSONEncoder().encode(file)
            let decoded = try JSONDecoder().decode(FrecencyFile.self, from: data)
            t.expectEqual(decoded.version, 1, "version")
            t.expect(decoded.entries[id] != nil, "entry present after round trip")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }
}
