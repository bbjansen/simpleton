// Sources/SimpletonSQL/SQLGridData.swift
import Foundation

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

    /// Original row indices in display order. `nil` sortColumn -> identity.
    /// Stable: equal keys keep original order (tie-broken by original index).
    public func sortedIndex(sortColumn: Int?, ascending: Bool) -> [Int] {
        let identity = Array(rows.indices)
        guard let col = sortColumn, columns.indices.contains(col) else { return identity }
        return identity.sorted { lhs, rhs in
            switch SQLCellFormatting.compare(value(row: lhs, column: col), value(row: rhs, column: col)) {
            case .orderedAscending: return ascending
            case .orderedDescending: return !ascending
            case .orderedSame: return lhs < rhs
            }
        }
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
