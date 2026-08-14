// Sources/SimpletonSQL/SQLGridData.swift
import Foundation

/// A grid cell address in the *original* (unsorted) coordinate space: the row's original index and
/// the result-column index. Staged edits are keyed by this so they survive re-sorting the grid.
public struct CellCoord: Sendable, Hashable {
    public let row: Int
    public let column: Int
    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }
}

/// Parses a user's typed cell text back into a `SQLValue` of the same kind as the column's current
/// value, so edits stay type-correct. Pure + headless: the grid calls this on Enter and either
/// stages the returned value or flashes the cell red when it returns nil (invalid for the type).
public enum SQLCellEditing {
    /// Parse `text` for a cell whose existing value is `existing`.
    /// - Numeric columns (integer/double) reject non-numeric text (→ nil).
    /// - Bool columns accept true/false/1/0/yes/no (case-insensitive); anything else → nil.
    /// - Text columns take the text verbatim (empty string stays empty text, distinct from NULL).
    /// - A NULL or blob cell edited as text becomes text (blobs aren't editable inline; the caller
    ///   gates that separately, but we still return a sensible value).
    public static func parse(_ text: String, like existing: SQLValue) -> SQLValue? {
        switch existing {
        case .integer:
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard let v = Int64(trimmed) else { return nil }
            return .integer(v)
        case .double:
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard let v = Double(trimmed) else { return nil }
            return .double(v)
        case .bool:
            switch text.trimmingCharacters(in: .whitespaces).lowercased() {
            case "true", "1", "yes", "t", "y": return .bool(true)
            case "false", "0", "no", "f", "n": return .bool(false)
            default: return nil
            }
        case .text, .null:
            return .text(text)
        case .blob:
            // Blobs aren't editable inline; keep the value unchanged if asked.
            return nil
        }
    }

    /// The string a cell shows while editing (what the text field is seeded with). NULL edits start
    /// empty; everything else uses its display form.
    public static func editingText(for value: SQLValue) -> String {
        if case .null = value { return "" }
        return SQLCellFormatting.present(value).text
    }
}

/// One column sort key: the column index and its direction. An ordered list of
/// these drives multi-column sort (primary first).
public struct SortKey: Sendable, Hashable {
    public let column: Int
    public let ascending: Bool
    public init(column: Int, ascending: Bool) {
        self.column = column
        self.ascending = ascending
    }
}

/// The data brain of the results grid: holds the materialized result and
/// derives display order, cell lookups, and TSV export. Pure and headless —
/// the AppKit grid Coordinator is thin glue over this.
public struct SQLGridData: Sendable {
    public let columns: [Column]
    public let rows: [[SQLValue]]

    public init(columns: [Column], rows: [[SQLValue]]) {
        self.columns = columns
        self.rows = rows
    }

    public var rowCount: Int { rows.count }
    public var columnCount: Int { columns.count }

    /// A stable, launch-independent signature of the column set (FNV-1a over the
    /// column names). Used to key persisted per-result column widths so a query
    /// with the same columns restores them, and a different query does not.
    public var columnSignature: String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in columns.map(\.name).joined(separator: "\u{1}").utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    /// Original row indices in display order for an ordered list of sort keys
    /// (primary first). Rows equal on every key keep their original order
    /// (stable). Out-of-range keys are ignored; empty keys → identity.
    public func sortedIndex(by keys: [SortKey]) -> [Int] {
        let identity = Array(rows.indices)
        let valid = keys.filter { columns.indices.contains($0.column) }
        guard !valid.isEmpty else { return identity }
        return identity.sorted { lhs, rhs in
            for key in valid {
                switch SQLCellFormatting.compare(
                    value(row: lhs, column: key.column), value(row: rhs, column: key.column))
                {
                case .orderedAscending: return key.ascending
                case .orderedDescending: return !key.ascending
                case .orderedSame: continue
                }
            }
            return lhs < rhs
        }
    }

    /// Columns that look categorical — every non-null value is text and there
    /// are 2…`maxDistinct` distinct values (sampled over the first `sampleRows`
    /// rows to stay cheap on huge results). The grid renders these as colored
    /// pills. A high-cardinality or non-text column bails early.
    public func enumColumns(maxDistinct: Int = 12, sampleRows: Int = 2000) -> Set<Int> {
        var result: Set<Int> = []
        let limit = min(rows.count, sampleRows)
        guard limit >= 2 else { return result }
        for c in columns.indices {
            var distinct = Set<String>()
            var qualifies = true
            for r in 0..<limit {
                switch value(row: r, column: c) {
                case .null: continue
                case .text(let s):
                    distinct.insert(s)
                    if distinct.count > maxDistinct { qualifies = false }
                default:
                    qualifies = false
                }
                if !qualifies { break }
            }
            if qualifies, distinct.count >= 2 { result.insert(c) }
        }
        return result
    }

    /// A stable palette slot (0..<slots) for a categorical value, so the same
    /// value always gets the same color. FNV-1a over the text.
    public func enumColorIndex(_ text: String, slots: Int) -> Int {
        guard slots > 0 else { return 0 }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        return Int(hash % UInt64(slots))
    }

    /// Single-column convenience over `sortedIndex(by:)`.
    public func sortedIndex(sortColumn: Int?, ascending: Bool) -> [Int] {
        guard let col = sortColumn else { return Array(rows.indices) }
        return sortedIndex(by: [SortKey(column: col, ascending: ascending)])
    }

    /// Bounds-safe cell lookup (`.null` when out of range).
    public func value(row: Int, column: Int) -> SQLValue {
        guard rows.indices.contains(row), rows[row].indices.contains(column) else { return .null }
        return rows[row][column]
    }

    /// TSV for the given original row indices, already in the desired order.
    /// NULL -> empty field; a field containing tab, newline, or a double-quote
    /// is wrapped in double quotes with internal quotes doubled (RFC 4180).
    public func tsv(rows rowIndices: [Int], withHeader: Bool) -> String {
        var lines: [String] = []
        if withHeader {
            lines.append(columns.map { escape($0.name) }.joined(separator: "\t"))
        }
        for r in rowIndices {
            let fields = columns.indices.map { c -> String in
                let v = value(row: r, column: c)
                if case .null = v { return "" }
                return escape(SQLCellFormatting.present(v).text)
            }
            lines.append(fields.joined(separator: "\t"))
        }
        return lines.joined(separator: "\n")
    }

    private func escape(_ field: String) -> String {
        guard field.contains("\t") || field.contains("\n") || field.contains("\r") || field.contains("\"") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
