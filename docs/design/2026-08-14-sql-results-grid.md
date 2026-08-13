# SQL Results Grid — Design

**Status:** approved for planning
**Date:** 2026-08-14
**Branch:** `feature/client-workbench`
**Replaces:** the primitive `SQLResultsGrid.swift` (a `ScrollView` of `HStack`/`Text` cells)

## Problem

The SQL panel's results area is a bare monospace text table: fixed-width
`Text` cells in nested `HStack`/`VStack`, no cell reuse, no sort, no
resize, no selection, no type awareness. It does not compete with
TablePlus / DataGrip / Postico / Beekeeper, and it does not scale past a
few hundred rows.

We replace it with a competitive, read-only results UI offering two view
modes behind a segmented toggle:

1. **Grid** — an Excel-like data grid: real cells, sticky header, a
   row-number gutter, resizable/reorderable/sortable columns, type-aware
   rendering (right-aligned tabular numbers, distinct NULL/EMPTY tokens,
   boolean glyphs), multi-row selection, and NULL-preserving TSV copy.
2. **Record** — the selected row's fields stacked label → value, filtered
   by field name, with prev/next stepping — for reading or scanning one
   wide row without horizontal scrolling.

## Goals

- Feel premium and native on macOS; theme live with the appearance system.
- Stay smooth on large result sets (tens of thousands of rows) via true
  cell reuse and a fixed row height.
- Keep all type/format/sort/copy logic **pure and headless-testable** in
  `SimpletonSQL`, so the AppKit layer is thin glue.
- Reuse the existing `QueryResult` model unchanged.

## Non-goals (v1 — deferred, not dropped)

- Inline cell editing, staged-edit tinting, commit/rollback (v1 is
  **read-only**; writes go through the query editor).
- True cell-range selection (v1 selects whole rows; `NSTableView` is
  row-based).
- Frozen/pinned first column (the row-number gutter scrolls with content).
- Multi-column sort (v1 is single-column).
- Column width/order persistence across queries.
- FK navigation, JSON tree pop-out, Quick Look for blobs, colored enum
  pills, pagination/LIMIT UI.

Each is a clean future addition on this foundation.

## The result model (existing, unchanged)

From `Sources/SimpletonSQL/SQLDriver.swift`:

```swift
public enum QueryResult: Sendable {
    case rows(columns: [Column], rows: [[SQLValue]])
    case status(affected: Int, message: String)
}
public struct Column: Sendable, Hashable {
    public let name: String
    public let declaredType: String?
}
public enum SQLValue: Sendable, Hashable {
    case null, integer(Int64), double(Double), text(String), bool(Bool), blob(Data)
    public var displayString: String { … }
}
```

The grid works over the already-materialized `.rows(columns:rows:)`. No
driver changes.

## Architecture

Five units, each with one responsibility. The pure logic lives in
`SimpletonSQL` (CoreChecks-testable); only layout + theming live in the
app module.

```
QueryResult? ──▶ SQLResultsView (app)
                   │ owns: mode, sort, selectedRow, density
                   ├── SQLDataGrid (app)      NSViewRepresentable → NSTableView
                   │      └── SQLGridData (SimpletonSQL, pure)
                   │             └── SQLCellFormatting (SimpletonSQL, pure)
                   └── SQLRecordView (app)     SwiftUI form
                          └── SQLCellFormatting (SimpletonSQL, pure)
```

### File structure

| File | Module | Responsibility |
|---|---|---|
| `Sources/SimpletonSQL/SQLCellFormatting.swift` | SimpletonSQL | Pure. `SQLValue` (+ `Column`) → `CellPresentation` (text, role, alignment, isNull, isEmptyText). Stable value comparator. |
| `Sources/SimpletonSQL/SQLGridData.swift` | SimpletonSQL | Pure. Holds `columns` + `rows`; computes `sortedIndex`; `value(row:col:)` through sort order; `tsv(rows:withHeader:)` (NULL-preserving, RFC-4180 quoting). |
| `Sources/Simpleton/Panels/SQL/SQLResultsView.swift` | Simpleton | Top-level container. `.none`/`.status`/empty states, results toolbar (Grid \| Record + density), shared view state. |
| `Sources/Simpleton/Panels/SQL/SQLDataGrid.swift` | Simpleton | `NSViewRepresentable` over `NSScrollView`+`NSTableView`; Coordinator dataSource/delegate; runtime columns; cell reuse; sort/resize/reorder/select/copy; themed. |
| `Sources/Simpleton/Panels/SQL/SQLRecordView.swift` | Simpleton | Record mode: selected row label→value form, field filter, prev/next stepper. |
| `Sources/Simpleton/Views/DesignTokens.swift` (edit) | Simpleton | `NSColor(hex:)` + a `DT.Grid` themed `NSColor` set + `DT.monoNSFont(size:)`. |

The old `Sources/Simpleton/Panels/SQL/SQLResultsGrid.swift` is deleted;
its `.status`/empty rendering moves into `SQLResultsView`. The call site
at `SQLPanelView.swift:62` changes from `SQLResultsGrid(result:)` to
`SQLResultsView(result:)`.

## Component detail

### `SQLCellFormatting` (pure)

```swift
public enum CellRole: Sendable, Hashable { case number, text, bool, null, blob }
public enum CellAlignment: Sendable, Hashable { case leading, trailing }

public struct CellPresentation: Sendable, Hashable {
    public let text: String          // "NULL", "", "42", "true"/"false", "<12 bytes>"
    public let role: CellRole
    public let alignment: CellAlignment
    public let isNull: Bool
    public let isEmptyText: Bool     // .text("") — rendered distinct from NULL
}

public enum SQLCellFormatting {
    public static func present(_ value: SQLValue) -> CellPresentation
    /// Stable, type-aware ordering. NULLs sort last on ascending. Mixed
    /// types ordered by a fixed role rank so sorting never traps.
    public static func compare(_ a: SQLValue, _ b: SQLValue) -> ComparisonResult
}
```

Role comes from the value case (reliable across engines); v1 does not use
`Column.declaredType` (a clean future refinement). `present` returns the
raw display text (`"true"`/`"false"` for bool); the *view* maps
`role == .bool` to a ✓/✗ glyph and applies color/font — `CellPresentation`
stays UI-framework-free.

Presentation rules:

| Value | role | alignment | text |
|---|---|---|---|
| `.integer(v)` / `.double(v)` | number | trailing | `displayString` (no thousands separators) |
| `.text(s)`, non-empty | text | leading | `s` |
| `.text("")` | text | leading | `""` (view shows a faint `(empty)` marker) |
| `.bool(b)` | bool | leading | `"true"`/`"false"` (view shows ✓/✗) |
| `.blob(d)` | blob | leading | `"<N bytes>"` |
| `.null` | null | leading | `"NULL"` |

Comparator ordering: numbers numerically; text lexicographically
(case-insensitive, then case-sensitive tiebreak for stability); bool
false < true; blob by byte count; NULL last (ascending). Cross-type
comparisons use a fixed role rank (`number < text < bool < blob < null`)
so a mixed column never produces an unstable or trapping sort.

### `SQLGridData` (pure)

```swift
public struct SQLGridData: Sendable {
    public let columns: [Column]
    public let rows: [[SQLValue]]
    public init(columns: [Column], rows: [[SQLValue]])

    public var rowCount: Int { rows.count }
    public var columnCount: Int { columns.count }
    /// Original row indices in display order (identity when `sortColumn == nil`).
    /// Stable: equal keys keep input order; tie-broken by original index.
    public func sortedIndex(sortColumn: Int?, ascending: Bool) -> [Int]
    /// The value at an original row/column (bounds-safe → `.null` if out of range).
    public func value(row: Int, column: Int) -> SQLValue
    /// TSV for the given original row indices, already in the desired order.
    /// NULL → empty field; cells containing tab/newline/`"` get RFC-4180
    /// double-quote quoting. `withHeader` prepends the column names.
    public func tsv(rows: [Int], withHeader: Bool) -> String
}
```

Sorting is **in-memory** over the materialized rows — we already hold every
row, so no `ORDER BY` re-query. `sortedIndex` is a stable sort keyed by
`SQLCellFormatting.compare`, tie-broken by original index. The Coordinator
holds `order = data.sortedIndex(...)` and maps display row → `order[row]`.
This struct is the data brain of the grid, tested directly by CoreChecks.

### `SQLDataGrid` (`NSViewRepresentable`)

- Wraps an `NSScrollView` hosting a view-based `NSTableView`.
  `drawsBackground = false` on both so the panel's `themedGlass` shows
  through (matches every other panel).
- **Runtime columns:** the Coordinator builds one `NSTableColumn` per
  `Column` (identifier = column index as string), plus a leading
  row-number gutter column. `allowsColumnResizing` and
  `allowsColumnReordering` on; default width ≈ 140, header-aware minimum.
- **Cell reuse:** one reused `NSTableCellView` subclass with an
  `NSTextField`; `makeView(withIdentifier:owner:)` recycles. Row height is
  **fixed** per density; `usesAutomaticRowHeights = false` (the biggest
  perf lever). Per-cell config reads `SQLCellFormatting.present` → sets
  text, alignment, color (role → themed `NSColor`), font
  (`DT.monoNSFont`), and the faint `(empty)`/`NULL` styling.
- **Sort:** each column's `sortDescriptorPrototype = NSSortDescriptor(key:
  "<index>", ascending: true)`; `tableView(_:sortDescriptorsDidChange:)`
  recomputes `SQLGridData.sortedIndex` and calls `reloadData()`.
  `NSTableView` renders the sort chevron on the active column.
- **Selection + copy:** `allowsMultipleSelection = true`, row-based, plus
  ⌘A. ⌘C copies `SQLGridData.tsv` for the selected display rows (no
  header); a right-click menu offers *Copy* and *Copy with Column Names*
  (header = true). Copy writes `.string` to `NSPasteboard.general`.
- **Live theme:** `updateNSView` re-applies the `DT.Grid` colors and calls
  `reloadData()` (visible rows only) when `ThemeSettings` changes, and
  reconciles column/row-height changes when the result or density changes.
  Rebuild columns only when the `columns` identity changes (not on every
  update).

### `SQLResultsView`

```swift
struct SQLResultsView: View {
    let result: QueryResult?
    @State private var mode: ResultsMode = .grid          // .grid | .record
    @State private var sortColumn: Int? = nil
    @State private var ascending = true
    @State private var selectedRow: Int? = nil
    @AppStorage("sql.grid.density") private var density: GridDensity = .comfortable
    @ObservedObject private var themeSettings = ThemeSettings.shared
}
```

- `.none` → "Run a query to see results." hint.
- `.status(affected, message)` → the existing checkmark + affected-rows
  line (moved verbatim from `SQLResultsGrid`).
- `.rows(_, [])` → "No rows." hint.
- `.rows(columns, rows)` → a slim results toolbar (Grid \| Record segmented
  control; density menu; row count) above the active mode.
- Record is disabled for empty/`.status` results. **Space** on the focused
  grid row switches to Record for that row; **Esc** returns to Grid.

`GridDensity`: `.compact` (row 22) / `.comfortable` (28, default) /
`.spacious` (34). Fixed heights; persisted via `@AppStorage`.

### `SQLRecordView`

Pure SwiftUI (one row — no virtualization needed). The selected row's
`(Column, SQLValue)` pairs as label → value rows: label = column name
(fixed leading width, truncating), value rendered through
`SQLCellFormatting` (NULL token, ✓/✗ for bool, tabular numbers, faint
`(empty)`), `.textSelection(.enabled)`. A field-name filter box at top; a
prev/next stepper showing "row *i* of *N*" that moves `selectedRow`.

## Theming

`DesignTokens.swift` gains, mirroring the existing SwiftUI tokens that read
`ThemeSettings.shared.theme.chrome` (reusing the existing `NSColor(hex:)`
in `ThemeApplier.swift`):

- `enum DT.Grid` themed `NSColor` accessors: `headerBackground`,
  `headerText`, `gridline` (hairline, low-opacity `border`), `rowText`
  (primary), `rowTextSecondary`, `nullText` (faint), `selectionFill`
  (`chrome.selected`). The focus ring uses the native first-responder ring.
- `DT.monoNSFont(size:weight:)` — an `NSFont` from
  `ThemeSettings.shared.monoFontFamily` (fallback
  `.monospacedSystemFont`), for tabular digits matching the terminal.

Refined-look rules baked in: **hairline 1px low-opacity dividers** (not
heavy gridlines); **zebra striping off by default** (it fights
hover/selection); sticky header; subtle hover; a selection tint (with the
native focus ring); right-aligned tabular numerals; a dim NULL token distinct from
`(empty)`; boolean glyphs. The table re-themes live because
`SQLResultsView` observes `ThemeSettings` and `updateNSView` re-applies
colors.

## Testing

**CoreChecks (headless, in `SimpletonSQL` — extends the existing suite):**

- `SQLCellFormatting.present`: role + alignment + text for each of the six
  `SQLValue` cases; `isNull` only for `.null`; `isEmptyText` only for
  `.text("")`; blob text is `<N bytes>`.
- `SQLCellFormatting.compare`: integers numeric (not lexical: 2 < 10);
  doubles numeric; text case-insensitive with stable tiebreak; bool
  false < true; blob by byte count; NULL last ascending; mixed-type by role
  rank; total stability (equal keys keep input order).
- `SQLGridData.sortedIndex`: identity when unsorted; correct + stable
  ascending/descending on a sample; NULLs land last ascending / first
  descending.
- `SQLGridData.value`: reads through the sorted order correctly.
- `SQLGridData.tsv`: values tab-joined, rows newline-joined; NULL → empty
  field; a cell with an embedded tab/newline/`"` is double-quote quoted
  with internal quotes doubled; `withHeader` prepends column names.

**Existing gates unchanged:** `swift build`, `swift run CoreChecks`,
`swift format lint --recursive --parallel --strict Sources Tests`. The
`scripts/e2e/sql-e2e.sh` connect/load harness stays green (untouched).

## Global constraints

- Swift 6 / SPM, no Xcode: `swift build`; `swift run CoreChecks`;
  `swift format lint --recursive --parallel --strict Sources Tests`.
- Pure logic (formatting, sort, grid data) lives in `SimpletonSQL` (no
  AppKit import there); only `SQLResultsView`/`SQLDataGrid`/`SQLRecordView`
  and the `DesignTokens` additions live in the app module.
- `QueryResult`/`SQLValue`/`Column` are unchanged; no driver changes.
- Theme via `DT`/`ThemeSettings`; the grid draws no background so
  `themedGlass` shows through, matching the other panels.
- Read-only: no editing, no writes from the grid.
- Commit messages conventional; no co-author; no Claude/AI mention.
