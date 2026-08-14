// Sources/SimpletonSQL/SQLRunStats.swift
import Foundation

/// Formats the "what just happened" readout for a completed query: a row/affected count plus how long
/// it took. Pure and headless so the number formatting (pluralization, sub-millisecond, seconds
/// rollover) is unit-tested without a UI.
public enum SQLRunStats {
    /// Whether `count` describes returned rows (a SELECT) or affected rows (an INSERT/UPDATE/DDL).
    public enum Noun: Sendable { case rows, affected }

    /// A compact summary like `"42 rows · 13 ms"`. Timing rolls over to seconds at ≥ 1 s and shows one
    /// decimal below 1 ms, so a fast query reads `"1 row · 0.4 ms"` rather than `"1 row · 0 ms"`.
    public static func summary(count: Int, noun: Noun, seconds: Double) -> String {
        "\(countText(count, noun)) · \(timeText(seconds))"
    }

    /// Just the timing portion (used when there is no row context, e.g. a bare readout).
    public static func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        if seconds >= 1 { return String(format: "%.2f s", seconds) }
        let ms = seconds * 1000
        return ms >= 1 ? String(format: "%.0f ms", ms) : String(format: "%.1f ms", ms)
    }

    private static func countText(_ count: Int, _ noun: Noun) -> String {
        switch noun {
        case .rows: return "\(count) row\(count == 1 ? "" : "s")"
        case .affected: return "\(count) affected"
        }
    }
}
