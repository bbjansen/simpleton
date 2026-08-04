// Tests/CoreChecks/FrecencyScorerChecks.swift
// Ported from Tests/SimpletonCoreTests/Core/FrecencyScorerTests.swift
import Foundation
import SimpletonCore

func runFrecencyScorerChecks(_ t: TestRunner) {
    t.suite("FrecencyScorer.testRecentUseScoresHighest") {
        let now = Date()
        let entry = FrecencyEntry(score: 0, lastUsed: now, useCount: 1, recentTimestamps: [now])
        let score = FrecencyScorer.computeScore(entry: entry, now: now)
        t.expectEqual(score, 100, "last 4 hours bucket")
    }

    t.suite("FrecencyScorer.testOlderUseScoresLower") {
        let now = Date()
        let twoDaysAgo = now.addingTimeInterval(-2 * 24 * 3600)
        let entry = FrecencyEntry(score: 0, lastUsed: twoDaysAgo, useCount: 1, recentTimestamps: [twoDaysAgo])
        let score = FrecencyScorer.computeScore(entry: entry, now: now)
        t.expectEqual(score, 60, "last 7 days bucket")
    }

    t.suite("FrecencyScorer.testMultipleUsesAccumulate") {
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
        t.expectEqual(score, 260, "100 + 100 + 60")
    }

    t.suite("FrecencyScorer.testOlderThan90DaysScoresZero") {
        let now = Date()
        let old = now.addingTimeInterval(-91 * 24 * 3600)
        let entry = FrecencyEntry(score: 0, lastUsed: old, useCount: 1, recentTimestamps: [old])
        let score = FrecencyScorer.computeScore(entry: entry, now: now)
        t.expectEqual(score, 0, "older than 90 days scores zero")
    }

    t.suite("FrecencyScorer.testRecordUseAddsTimestamp") {
        var entry = FrecencyEntry()
        let now = Date()
        entry = FrecencyScorer.recordUse(entry: entry, now: now)
        t.expectEqual(entry.useCount, 1, "useCount incremented")
        t.expectEqual(entry.recentTimestamps.count, 1, "timestamp recorded")
        t.expectEqual(entry.lastUsed, now, "lastUsed set to now")
    }

    t.suite("FrecencyScorer.testRecordUseCapsAt100Timestamps") {
        var entry = FrecencyEntry()
        let now = Date()
        for i in 0..<110 {
            entry = FrecencyScorer.recordUse(entry: entry, now: now.addingTimeInterval(Double(i)))
        }
        t.expectEqual(entry.recentTimestamps.count, 100, "timestamps capped at 100")
        t.expectEqual(entry.useCount, 110, "useCount still counts all uses")
    }

    t.suite("FrecencyScorer.testPruneRemovesOldEntries") {
        let now = Date()
        let old = now.addingTimeInterval(-91 * 24 * 3600)
        let entry = FrecencyEntry(score: 20, lastUsed: old, useCount: 1, recentTimestamps: [old])
        let pruned = FrecencyScorer.prune(entry: entry, now: now)
        t.expect(pruned == nil, "score 0 -> pruned")
    }
}
