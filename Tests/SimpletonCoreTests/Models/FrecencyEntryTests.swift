// Tests/SimpletonCoreTests/Models/FrecencyEntryTests.swift
import XCTest
@testable import SimpletonCore

final class FrecencyEntryTests: XCTestCase {

    func testFrecencyEntryRoundTrip() throws {
        let entry = FrecencyEntry(
            score: 245.8,
            lastUsed: Date(),
            useCount: 47,
            recentTimestamps: [Date(), Date().addingTimeInterval(-3600)]
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(FrecencyEntry.self, from: data)
        XCTAssertEqual(decoded.useCount, 47)
        XCTAssertEqual(decoded.recentTimestamps.count, 2)
    }

    func testFrecencyFileRoundTrip() throws {
        let id = UUID()
        let file = FrecencyFile(entries: [id: FrecencyEntry(score: 100, lastUsed: Date(), useCount: 5, recentTimestamps: [])])
        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(FrecencyFile.self, from: data)
        XCTAssertEqual(decoded.version, 1)
        XCTAssertNotNil(decoded.entries[id])
    }
}
