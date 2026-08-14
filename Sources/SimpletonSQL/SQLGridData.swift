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

/// The fully-resolved, UI-framework-free instructions for rendering one grid cell: which value to
/// show (already resolving staged edits over the committed value), its presentation, whether it is a
/// staged edit (amber tint), and — for a categorical column — a stable palette *slot* (the view layer
/// maps the slot to a concrete color, so this stays free of AppKit). Computed once by
/// `SQLGridData.cellStyle` and consumed identically by the main grid and the frozen first-column pane,
/// so pills, edit-tint, alignment, and fonts can never drift between the two panes.
public struct GridCellStyle: Sendable, Hashable {
    /// How to present the effective value (text, role, alignment, null/empty flags).
    public let presentation: CellPresentation
    /// True when the effective value is a staged (uncommitted) edit → render with the amber tint.
    public let isStaged: Bool
    /// A palette slot for a categorical (enum) cell, or nil when the cell is not an enum pill. Only set
    /// for a non-staged, non-empty text value in an enum column; the view maps it to a color.
    public let enumSlot: Int?

    public init(presentation: CellPresentation, isStaged: Bool, enumSlot: Int?) {
        self.presentation = presentation
        self.isStaged = isStaged
        self.enumSlot = enumSlot
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

/// Half-open bounds of a display page over an ordered row list: `[start, end)`, plus the total row
/// count and the resolved (clamped) page index. `count` is the number of rows on the page.
public struct PageBounds: Sendable, Hashable {
    public let start: Int
    public let end: Int
    public let total: Int
    public let page: Int
    public init(start: Int, end: Int, total: Int, page: Int) {
        self.start = start
        self.end = end
        self.total = total
        self.page = page
    }

    /// Rows on this page (`end - start`).
    public var count: Int { end - start }
    /// Whether the page is empty (no rows in range).
    public var isEmpty: Bool { count <= 0 }
    /// 1-based index of the first row on the page (0 when empty) — for "Rows X–Y of N".
    public var firstRowNumber: Int { isEmpty ? 0 : start + 1 }
    /// 1-based index of the last row on the page (0 when empty).
    public var lastRowNumber: Int { end }
}

/// Pure geometry + column-mapping for the frozen left pane (row-number gutter + the first data
/// column). Split out so the layout math is unit-tested without AppKit. The frozen data column is
/// whatever sits at view position 0 (the leftmost column), so it tracks the user's column reordering.
public enum FrozenColumnGeometry {
    /// The total width of the frozen pane: the gutter strip plus the frozen data column's width. This
    /// is the left content inset the main table needs so its columns never slide under the pane.
    public static func paneWidth(gutter: CGFloat, frozenColumnWidth: CGFloat) -> CGFloat {
        max(0, gutter) + max(0, frozenColumnWidth)
    }

    /// Whether a table column at `viewPosition` is the frozen one (always the leftmost, position 0).
    /// The main table hides this column and the frozen pane renders it, so they never both draw it.
    public static func isFrozen(viewPosition: Int) -> Bool { viewPosition == 0 }

    /// The x-origin of the frozen data column inside the pane (just right of the gutter). The gutter
    /// occupies `[0, gutter)`; the frozen data column occupies `[gutter, gutter + width)`.
    public static func frozenColumnOriginX(gutter: CGFloat) -> CGFloat { max(0, gutter) }
}

/// Pure pagination math over a sorted row order. A page size of `nil` (or ≤ 0) means "All rows on one
/// page". The page index is clamped into `[0, pageCount)`, so an out-of-range page (e.g. after the
/// result shrinks) resolves to the last valid page rather than trapping.
public enum SQLPaging {
    /// Number of pages for `total` rows at `pageSize` (`nil`/≤0 → 1 page). Always ≥ 1.
    public static func pageCount(total: Int, pageSize: Int?) -> Int {
        guard let size = pageSize, size > 0, total > 0 else { return 1 }
        return (total + size - 1) / size
    }

    /// Resolve the half-open bounds of `page` (0-based) over `total` sorted rows at `pageSize`.
    /// `pageSize == nil` (or ≤ 0) yields the whole range `[0, total)`. The page is clamped so callers
    /// never index out of range.
    public static func bounds(total: Int, pageSize: Int?, page: Int) -> PageBounds {
        guard total > 0 else { return PageBounds(start: 0, end: 0, total: 0, page: 0) }
        guard let size = pageSize, size > 0 else {
            return PageBounds(start: 0, end: total, total: total, page: 0)
        }
        let pages = pageCount(total: total, pageSize: size)
        let clamped = min(max(page, 0), pages - 1)
        let start = clamped * size
        let end = min(start + size, total)
        return PageBounds(start: start, end: end, total: total, page: clamped)
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

    /// The complete render instructions for the cell at `(row, column)` in original coordinates. This
    /// is the single source of truth both grid panes use, so their pills/tints/alignment stay in sync:
    /// it resolves the staged edit over the committed value, presents it, flags a staged edit, and —
    /// only for a non-staged, non-empty text value in an `enumColumns` column — assigns a stable
    /// palette slot (via `enumColorIndex`). `stagedValue` is the staged edit for this coord (or nil);
    /// `enumColumns` and `enumSlots` come from the grid's one-time column analysis and palette size.
    public func cellStyle(
        row: Int, column: Int, stagedValue: SQLValue?, enumColumns: Set<Int>, enumSlots: Int
    ) -> GridCellStyle {
        let effective = stagedValue ?? value(row: row, column: column)
        let presentation = SQLCellFormatting.present(effective)
        // Enum pill only when this is the committed value (not a staged edit) in an enum column and the
        // value is non-empty text — matching the original inline rule exactly.
        var slot: Int?
        if stagedValue == nil, enumSlots > 0, enumColumns.contains(column),
            case .text(let s) = effective, !s.isEmpty
        {
            slot = enumColorIndex(s, slots: enumSlots)
        }
        return GridCellStyle(presentation: presentation, isStaged: stagedValue != nil, enumSlot: slot)
    }

    /// TSV for the given original row indices, already in the desired order.
    /// NULL -> empty field; a field containing tab, newline, or a double-quote
    /// is wrapped in double quotes with internal quotes doubled (RFC 4180).
    public func tsv(rows rowIndices: [Int], withHeader: Bool) -> String {
        tsv(rows: rowIndices, columns: Array(columns.indices), withHeader: withHeader)
    }

    /// Rectangular TSV: the given original row indices (already ordered) crossed with the given column
    /// indices (already ordered). Powers cell-range copy — a rubber-band selection maps to a set of
    /// display rows (→ original rows) and a contiguous column span. Out-of-range column indices are
    /// skipped; NULL/quoting rules match the whole-row `tsv`.
    public func tsv(rows rowIndices: [Int], columns columnIndices: [Int], withHeader: Bool) -> String {
        let cols = columnIndices.filter { columns.indices.contains($0) }
        var lines: [String] = []
        if withHeader {
            lines.append(cols.map { escape(columns[$0].name) }.joined(separator: "\t"))
        }
        for r in rowIndices {
            let fields = cols.map { c -> String in
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
