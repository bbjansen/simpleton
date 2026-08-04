// Sources/SimpletonCore/Core/FuzzyMatcher.swift
import Foundation

public enum FuzzyMatcher {

    /// Returns a score > 0 if query fuzzy-matches candidate, nil if no match.
    /// Higher score = better match.
    public static func score(query: String, candidate: String) -> Double? {
        if query.isEmpty { return 1.0 }

        let q = query.lowercased()
        let c = candidate.lowercased()

        // Check subsequence match
        var qi = q.startIndex
        for ci in c.indices {
            if c[ci] == q[qi] {
                qi = q.index(after: qi)
                if qi == q.endIndex { break }
            }
        }
        guard qi == q.endIndex else { return nil }

        // Score based on match quality
        var matchScore: Double = 0

        if c == q {
            matchScore = 1000  // exact match
        } else if c.hasPrefix(q) {
            matchScore = 900  // prefix match
        } else if c.contains(q) {
            matchScore = 800  // substring match
        } else {
            // subsequence match — score based on gap count
            var gaps = 0
            var lastMatchIndex: String.Index?
            var qIdx = q.startIndex
            for cIdx in c.indices {
                if qIdx < q.endIndex && c[cIdx] == q[qIdx] {
                    if let last = lastMatchIndex, c.distance(from: last, to: cIdx) > 1 {
                        gaps += 1
                    }
                    lastMatchIndex = cIdx
                    qIdx = q.index(after: qIdx)
                }
            }
            matchScore = max(100 - Double(gaps) * 10, 1)
        }

        // Bonus for shorter candidates (more relevant)
        let lengthBonus = 100.0 / Double(max(c.count, 1))
        return matchScore + lengthBonus
    }
}
