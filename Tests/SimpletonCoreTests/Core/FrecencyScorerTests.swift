// Tests/SimpletonCoreTests/Core/FrecencyScorerTests.swift
import XCTest

@testable import SimpletonCore

final class FrecencyScorerTests: XCTestCase {

    func testRecentUseScoresHighest() {
        let now = Date()
        let entry = FrecencyEntry(
            score: 0,
            lastUsed: now,
            useCount: 1,
            recentTimestamps: [now]
        )
        let score = FrecencyScorer.computeScore(entry: entry, now: now)
        XCTAssertEqual(score, 100)  // last 4 hours bucket
    }

    func testOlderUseScoresLower() {
        let now = Date()
        let twoDaysAgo = now.addingTimeInterval(-2 * 24 * 3600)
        let entry = FrecencyEntry(
            score: 0,
            lastUsed: twoDaysAgo,
            useCount: 1,
            recentTimestamps: [twoDaysAgo]
        )
        let score = FrecencyScorer.computeScore(entry: entry, now: now)
        XCTAssertEqual(score, 60)  // last 7 days bucket
    }

    func testMultipleUsesAccumulate() {
        let now = Date()
        let entry = FrecencyEntry(
            score: 0,
            lastUsed: now,
            useCount: 3,
            recentTimestamps: [
                now,
                now.addingTimeInterval(-3600),  // 1h ago, still in 4h bucket
                now.addingTimeInterval(-25 * 3600),  // 25h ago, in 7d bucket
            ]
        )
        let score = FrecencyScorer.computeScore(entry: entry, now: now)
        XCTAssertEqual(score, 260)  // 100 + 100 + 60
    }

    func testOlderThan90DaysScoresZero() {
        let now = Date()
        let old = now.addingTimeInterval(-91 * 24 * 3600)
        let entry = FrecencyEntry(score: 0, lastUsed: old, useCount: 1, recentTimestamps: [old])
        let score = FrecencyScorer.computeScore(entry: entry, now: now)
        XCTAssertEqual(score, 0)
    }

    func testRecordUseAddsTimestamp() {
        var entry = FrecencyEntry()
        let now = Date()
        entry = FrecencyScorer.recordUse(entry: entry, now: now)
        XCTAssertEqual(entry.useCount, 1)
        XCTAssertEqual(entry.recentTimestamps.count, 1)
        XCTAssertEqual(entry.lastUsed, now)
    }

    func testRecordUseCapsAt100Timestamps() {
        var entry = FrecencyEntry()
        let now = Date()
        for i in 0..<110 {
            entry = FrecencyScorer.recordUse(entry: entry, now: now.addingTimeInterval(Double(i)))
        }
        XCTAssertEqual(entry.recentTimestamps.count, 100)
        XCTAssertEqual(entry.useCount, 110)
    }

    func testPruneRemovesOldEntries() {
        let now = Date()
        let old = now.addingTimeInterval(-91 * 24 * 3600)
        let entry = FrecencyEntry(score: 20, lastUsed: old, useCount: 1, recentTimestamps: [old])
        let pruned = FrecencyScorer.prune(entry: entry, now: now)
        XCTAssertNil(pruned)  // score 0 → pruned
    }
}
