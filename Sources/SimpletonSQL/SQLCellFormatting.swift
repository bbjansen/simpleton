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
}
