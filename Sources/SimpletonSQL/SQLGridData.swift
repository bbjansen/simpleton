// Sources/SimpletonSQL/SQLGridData.swift
import Foundation

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
