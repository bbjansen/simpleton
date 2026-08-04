// Sources/SimpletonCore/Core/FrecencyScorer.swift
import Foundation

public enum FrecencyScorer {

    private static let buckets: [(maxAge: TimeInterval, points: Double)] = [
        (4 * 3600, 100),  // last 4 hours
        (24 * 3600, 80),  // last 24 hours
        (7 * 24 * 3600, 60),  // last 7 days
        (30 * 24 * 3600, 40),  // last 30 days
        (90 * 24 * 3600, 20),  // last 90 days
    ]

    public static func computeScore(entry: FrecencyEntry, now: Date = Date()) -> Double {
        var total: Double = 0
        for timestamp in entry.recentTimestamps {
            let age = now.timeIntervalSince(timestamp)
            let points = buckets.first(where: { age <= $0.maxAge })?.points ?? 0
            total += points
        }
        return total
    }

    public static func recordUse(entry: FrecencyEntry, now: Date = Date()) -> FrecencyEntry {
        var updated = entry
        updated.lastUsed = now
        updated.useCount += 1
        updated.recentTimestamps.insert(now, at: 0)
        if updated.recentTimestamps.count > 100 {
            updated.recentTimestamps = Array(updated.recentTimestamps.prefix(100))
        }
        updated.score = computeScore(entry: updated, now: now)
        return updated
    }

    /// Returns nil if the entry should be pruned (score is 0).
    public static func prune(entry: FrecencyEntry, now: Date = Date()) -> FrecencyEntry? {
        let maxAge = 90 * 24 * 3600.0
        var updated = entry
        updated.recentTimestamps = updated.recentTimestamps.filter { now.timeIntervalSince($0) <= maxAge }
        updated.score = computeScore(entry: updated, now: now)
        return updated.score > 0 ? updated : nil
    }
}
