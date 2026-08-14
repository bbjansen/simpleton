// Sources/SimpletonSQL/SQLCellFormatting.swift
import Foundation

/// Role of a cell value — drives color and font in the view layer.
public enum CellRole: Sendable, Hashable { case number, text, bool, null, blob }

/// Horizontal alignment for a cell.
public enum CellAlignment: Sendable, Hashable { case leading, trailing }

/// A UI-framework-free description of how to present one cell value. Shared by
/// the AppKit grid and the SwiftUI record view; testable headlessly.
public struct CellPresentation: Sendable, Hashable {
    public let text: String
    public let role: CellRole
    public let alignment: CellAlignment
    public let isNull: Bool
    public let isEmptyText: Bool

    public init(text: String, role: CellRole, alignment: CellAlignment, isNull: Bool, isEmptyText: Bool) {
        self.text = text
        self.role = role
        self.alignment = alignment
        self.isNull = isNull
        self.isEmptyText = isEmptyText
    }
}

/// Pure presentation + ordering for SQL cell values.
public enum SQLCellFormatting {
    /// Presentation for a value. Role comes from the value case; numbers are
    /// trailing-aligned (tabular), everything else leading. `.text("")` is
    /// flagged `isEmptyText` so the view can distinguish it from NULL.
    public static func present(_ value: SQLValue) -> CellPresentation {
        switch value {
        case .null:
            return CellPresentation(text: "NULL", role: .null, alignment: .leading, isNull: true, isEmptyText: false)
        case .integer(let v):
            return CellPresentation(
                text: String(v), role: .number, alignment: .trailing, isNull: false, isEmptyText: false)
        case .double(let v):
            return CellPresentation(
                text: String(v), role: .number, alignment: .trailing, isNull: false, isEmptyText: false)
        case .text(let s):
            return CellPresentation(text: s, role: .text, alignment: .leading, isNull: false, isEmptyText: s.isEmpty)
        case .bool(let b):
            return CellPresentation(
                text: b ? "true" : "false", role: .bool, alignment: .leading, isNull: false, isEmptyText: false)
        case .blob(let d):
            return CellPresentation(
                text: "<\(d.count) bytes>", role: .blob, alignment: .leading, isNull: false, isEmptyText: false)
        }
    }

    /// Stable, type-aware ordering for column sort. Different types are ranked
    /// number < text < bool < blob < null, so NULLs sort last ascending and a
    /// mixed column never traps.
    public static func compare(_ a: SQLValue, _ b: SQLValue) -> ComparisonResult {
        let ra = rank(a), rb = rank(b)
        if ra != rb { return ra < rb ? .orderedAscending : .orderedDescending }
        switch (a, b) {
        case (.null, .null):
            return .orderedSame
        case let (.integer(x), .integer(y)):
            // Compare Int64 directly — routing through Double would lose precision
            // above 2^53 (Snowflake IDs, large keys, epoch-ns timestamps).
            if x == y { return .orderedSame }
            return x < y ? .orderedAscending : .orderedDescending
        case let (.bool(x), .bool(y)):
            if x == y { return .orderedSame }
            return (!x && y) ? .orderedAscending : .orderedDescending
        case let (.blob(x), .blob(y)):
            if x.count == y.count { return .orderedSame }
            return x.count < y.count ? .orderedAscending : .orderedDescending
        case let (.text(x), .text(y)):
            let ci = x.caseInsensitiveCompare(y)
            if ci != .orderedSame { return ci }
            if x == y { return .orderedSame }
            return x < y ? .orderedAscending : .orderedDescending
        default:
            let dx = numeric(a), dy = numeric(b)
            if dx == dy { return .orderedSame }
            return dx < dy ? .orderedAscending : .orderedDescending
        }
    }

    /// Cross-type sort rank: number(0) < text(1) < bool(2) < blob(3) < null(4).
    private static func rank(_ v: SQLValue) -> Int {
        switch v {
        case .integer, .double: return 0
        case .text: return 1
        case .bool: return 2
        case .blob: return 3
        case .null: return 4
        }
    }

    private static func numeric(_ v: SQLValue) -> Double {
        switch v {
        case .integer(let i): return Double(i)
        case .double(let d): return d
        default: return 0
        }
    }

    /// If `text` is a JSON object or array, return it pretty-printed (sorted keys); else nil.
    /// Used by the cell inspector to render JSON columns readably.
    public static func prettyJSON(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "{" || first == "[" else { return nil }
        guard let data = trimmed.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(
                withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
            let out = String(data: pretty, encoding: .utf8)
        else { return nil }
        return out
    }

    /// A classic `offset  hex  ascii` dump of `data`, truncated to `maxBytes` with a trailing note.
    public static func hexDump(_ data: Data, maxBytes: Int = 4096) -> String {
        let bytes = Array(data.prefix(maxBytes))
        var lines: [String] = []
        var offset = 0
        while offset < bytes.count {
            let chunk = bytes[offset..<min(offset + 16, bytes.count)]
            let hex = chunk.map { String(format: "%02x", $0) }.joined(separator: " ")
            let hexPadded = hex.padding(toLength: 47, withPad: " ", startingAt: 0)
            let ascii = chunk.map { (32...126).contains($0) ? String(UnicodeScalar($0)) : "." }.joined()
            lines.append("\(String(format: "%08x", offset))  \(hexPadded)  \(ascii)")
            offset += 16
        }
        var out = lines.joined(separator: "\n")
        if data.count > maxBytes { out += "\n… (\(data.count - maxBytes) more bytes)" }
        return out
    }
}
