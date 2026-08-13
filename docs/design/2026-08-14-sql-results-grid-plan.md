# SQL Results Grid Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the primitive `SQLResultsGrid` with a competitive, read-only results UI — an Excel-like `NSTableView` grid and a record/form mode behind a segmented toggle.

**Architecture:** All type/format/sort/copy logic is pure and lives in `SimpletonSQL` (`SQLCellFormatting`, `SQLGridData`), verified headlessly by CoreChecks. The AppKit `NSTableView` grid (`SQLDataGrid`) and the SwiftUI record view (`SQLRecordView`) are thin glue over that data, hosted by `SQLResultsView` inside the existing SQL panel. The grid uses runtime columns, fixed row height + cell reuse, in-memory sort, and themed `NSColor`s.

**Tech Stack:** Swift 6, SPM (no Xcode), AppKit `NSTableView` via `NSViewRepresentable`, SwiftUI, the app's `DT`/`ThemeSettings` theming, CoreChecks headless test runner.

**Spec:** `docs/design/2026-08-14-sql-results-grid.md`

## Global Constraints

- Swift 6 / SPM, no Xcode. Build: `swift build`. Tests: `swift run CoreChecks`. Lint: `swift format lint --recursive --parallel --strict Sources Tests`.
- Pure logic (formatting, sort, grid data) lives in `SimpletonSQL` with **no AppKit import**; only the view files and `DesignTokens` additions live in the `Simpleton` app module.
- `QueryResult` / `SQLValue` / `Column` are **unchanged**; no driver changes.
- Theme via `DT` / `ThemeSettings`; the grid draws **no background** so `themedGlass` shows through, matching the other panels. Reuse the existing `NSColor(hex:)` in `ThemeApplier.swift` — do not add another.
- Read-only: no editing, no writes from the grid.
- New CoreChecks are registered in `Tests/CoreChecks/main.swift` under the synchronous "Models" section.
- Deployment target is macOS 14+ (the codebase already uses the single-param `onChange(of:)`); AppKit APIs used here (`NSTableView.Style.plain`, `usesAutomaticRowHeights`, `onExitCommand`) are all available.
- Commit messages conventional; **no co-author; no Claude/AI mention**.

---

### Task 1: `SQLCellFormatting` — pure presentation + comparator

**Files:**
- Create: `Sources/SimpletonSQL/SQLCellFormatting.swift`
- Test: `Tests/CoreChecks/SQLCellFormattingChecks.swift`
- Modify: `Tests/CoreChecks/main.swift` (register the suite)

**Interfaces:**
- Consumes: `SQLValue` (from `Sources/SimpletonSQL/SQLDriver.swift`).
- Produces:
  - `enum CellRole: Sendable, Hashable { case number, text, bool, null, blob }`
  - `enum CellAlignment: Sendable, Hashable { case leading, trailing }`
  - `struct CellPresentation: Sendable, Hashable { let text: String; let role: CellRole; let alignment: CellAlignment; let isNull: Bool; let isEmptyText: Bool }`
  - `enum SQLCellFormatting { static func present(_ value: SQLValue) -> CellPresentation; static func compare(_ a: SQLValue, _ b: SQLValue) -> ComparisonResult }`

- [ ] **Step 1: Write the failing test**

Create `Tests/CoreChecks/SQLCellFormattingChecks.swift`:

```swift
import Foundation
import SimpletonSQL

func runSQLCellFormattingChecks(_ t: TestRunner) {
    t.suite("SQLCellFormatting.present") {
        let n = SQLCellFormatting.present(.integer(42))
        t.expectEqual(n.role, .number, "integer role")
        t.expectEqual(n.alignment, .trailing, "integer alignment")
        t.expectEqual(n.text, "42", "integer text")
        t.expect(!n.isNull, "integer not null")

        let d = SQLCellFormatting.present(.double(3.5))
        t.expectEqual(d.role, .number, "double role")
        t.expectEqual(d.alignment, .trailing, "double alignment")

        let s = SQLCellFormatting.present(.text("hi"))
        t.expectEqual(s.role, .text, "text role")
        t.expectEqual(s.alignment, .leading, "text alignment")
        t.expect(!s.isEmptyText, "non-empty text")

        let empty = SQLCellFormatting.present(.text(""))
        t.expect(empty.isEmptyText, "empty text flagged")
        t.expect(!empty.isNull, "empty text is not null")

        let b = SQLCellFormatting.present(.bool(true))
        t.expectEqual(b.role, .bool, "bool role")
        t.expectEqual(b.text, "true", "bool text")

        let bl = SQLCellFormatting.present(.blob(Data([1, 2, 3])))
        t.expectEqual(bl.role, .blob, "blob role")
        t.expectEqual(bl.text, "<3 bytes>", "blob text")

        let nul = SQLCellFormatting.present(.null)
        t.expectEqual(nul.role, .null, "null role")
        t.expect(nul.isNull, "null flagged")
        t.expectEqual(nul.text, "NULL", "null text")
    }

    t.suite("SQLCellFormatting.compare") {
        t.expectEqual(SQLCellFormatting.compare(.integer(2), .integer(10)), .orderedAscending, "2 < 10 numeric")
        t.expectEqual(SQLCellFormatting.compare(.integer(10), .integer(2)), .orderedDescending, "10 > 2")
        t.expectEqual(SQLCellFormatting.compare(.integer(2), .double(2.5)), .orderedAscending, "2 < 2.5 mixed")
        t.expectEqual(SQLCellFormatting.compare(.text("apple"), .text("Banana")), .orderedAscending, "apple < Banana ci")
        t.expectEqual(SQLCellFormatting.compare(.bool(false), .bool(true)), .orderedAscending, "false < true")
        t.expectEqual(SQLCellFormatting.compare(.blob(Data([1])), .blob(Data([1, 2]))), .orderedAscending, "1 byte < 2 bytes")
        t.expectEqual(SQLCellFormatting.compare(.integer(1), .null), .orderedAscending, "value before null")
        t.expectEqual(SQLCellFormatting.compare(.null, .integer(1)), .orderedDescending, "null after value")
        t.expectEqual(SQLCellFormatting.compare(.null, .null), .orderedSame, "null == null")
        t.expectEqual(SQLCellFormatting.compare(.integer(9), .text("a")), .orderedAscending, "number < text")
        t.expectEqual(SQLCellFormatting.compare(.text("z"), .bool(false)), .orderedAscending, "text < bool")
        t.expectEqual(SQLCellFormatting.compare(.bool(true), .blob(Data())), .orderedAscending, "bool < blob")
    }
}
```

Register it in `Tests/CoreChecks/main.swift` — add this line in the "Models (synchronous)" block (e.g. right after `runSQLClientCommandChecks(runner)`):

```swift
runSQLCellFormattingChecks(runner)
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift run CoreChecks`
Expected: FAIL to build — `cannot find 'SQLCellFormatting' in scope` (and `CellRole`/`CellPresentation`).

- [ ] **Step 3: Write the implementation**

Create `Sources/SimpletonSQL/SQLCellFormatting.swift`:

```swift
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
            return CellPresentation(text: String(v), role: .number, alignment: .trailing, isNull: false, isEmptyText: false)
        case .double(let v):
            return CellPresentation(text: String(v), role: .number, alignment: .trailing, isNull: false, isEmptyText: false)
        case .text(let s):
            return CellPresentation(text: s, role: .text, alignment: .leading, isNull: false, isEmptyText: s.isEmpty)
        case .bool(let b):
            return CellPresentation(text: b ? "true" : "false", role: .bool, alignment: .leading, isNull: false, isEmptyText: false)
        case .blob(let d):
            return CellPresentation(text: "<\(d.count) bytes>", role: .blob, alignment: .leading, isNull: false, isEmptyText: false)
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
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift run CoreChecks`
Expected: PASS — all new `SQLCellFormatting.*` checks pass; the total check count rises.

- [ ] **Step 5: Lint**

Run: `swift format lint --recursive --parallel --strict Sources Tests`
Expected: no output (clean).

- [ ] **Step 6: Commit**

```bash
git add Sources/SimpletonSQL/SQLCellFormatting.swift Tests/CoreChecks/SQLCellFormattingChecks.swift Tests/CoreChecks/main.swift
git commit -m "feat(sql): pure cell presentation + type-aware sort comparator"
```

---

### Task 2: `SQLGridData` — sorted index, cell lookup, TSV

**Files:**
- Create: `Sources/SimpletonSQL/SQLGridData.swift`
- Test: `Tests/CoreChecks/SQLGridDataChecks.swift`
- Modify: `Tests/CoreChecks/main.swift` (register the suite)

**Interfaces:**
- Consumes: `Column`, `SQLValue` (SQLDriver.swift); `SQLCellFormatting.compare` (Task 1); `SQLCellFormatting.present(_:).text` for TSV field text.
- Produces:
  - `struct SQLGridData: Sendable { let columns: [Column]; let rows: [[SQLValue]]; init(columns:rows:); var rowCount: Int; var columnCount: Int; func sortedIndex(sortColumn: Int?, ascending: Bool) -> [Int]; func value(row: Int, column: Int) -> SQLValue; func tsv(rows: [Int], withHeader: Bool) -> String }`

- [ ] **Step 1: Write the failing test**

Create `Tests/CoreChecks/SQLGridDataChecks.swift`:

```swift
import Foundation
import SimpletonSQL

func runSQLGridDataChecks(_ t: TestRunner) {
    let columns = [Column(name: "id"), Column(name: "name")]
    let rows: [[SQLValue]] = [
        [.integer(10), .text("banana")],
        [.integer(2), .text("apple")],
        [.null, .text("cherry")],
    ]
    let data = SQLGridData(columns: columns, rows: rows)

    t.suite("SQLGridData basics") {
        t.expectEqual(data.rowCount, 3, "row count")
        t.expectEqual(data.columnCount, 2, "column count")
        t.expectEqual(data.value(row: 0, column: 0), SQLValue.integer(10), "value(0,0)")
        t.expectEqual(data.value(row: 99, column: 0), SQLValue.null, "OOB row -> null")
    }

    t.suite("SQLGridData.sortedIndex") {
        t.expectEqual(data.sortedIndex(sortColumn: nil, ascending: true), [0, 1, 2], "identity when unsorted")
        t.expectEqual(data.sortedIndex(sortColumn: 0, ascending: true), [1, 0, 2], "id asc, null last")
        t.expectEqual(data.sortedIndex(sortColumn: 0, ascending: false), [2, 0, 1], "id desc, null first")
        t.expectEqual(data.sortedIndex(sortColumn: 1, ascending: true), [1, 0, 2], "name asc")
    }

    t.suite("SQLGridData.tsv") {
        let order = data.sortedIndex(sortColumn: 0, ascending: true)  // [1, 0, 2]
        let out = data.tsv(rows: order, withHeader: true)
        let expected = "id\tname\n2\tapple\n10\tbanana\n\tcherry"
        t.expectEqual(out, expected, "tsv with header, null as empty")

        let quoted = SQLGridData(columns: [Column(name: "c")], rows: [[.text("a\tb")]])
        t.expectEqual(quoted.tsv(rows: [0], withHeader: false), "\"a\tb\"", "tab value quoted")

        let q2 = SQLGridData(columns: [Column(name: "c")], rows: [[.text("he said \"hi\"")]])
        t.expectEqual(q2.tsv(rows: [0], withHeader: false), "\"he said \"\"hi\"\"\"", "embedded quote doubled")
    }
}
```

Register in `Tests/CoreChecks/main.swift` (right after `runSQLCellFormattingChecks(runner)`):

```swift
runSQLGridDataChecks(runner)
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift run CoreChecks`
Expected: FAIL to build — `cannot find 'SQLGridData' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/SimpletonSQL/SQLGridData.swift`:

```swift
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
        guard field.contains("\t") || field.contains("\n") || field.contains("\"") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift run CoreChecks`
Expected: PASS — all `SQLGridData.*` checks pass.

- [ ] **Step 5: Lint**

Run: `swift format lint --recursive --parallel --strict Sources Tests`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add Sources/SimpletonSQL/SQLGridData.swift Tests/CoreChecks/SQLGridDataChecks.swift Tests/CoreChecks/main.swift
git commit -m "feat(sql): SQLGridData — in-memory sort order, cell lookup, TSV export"
```

---

### Task 3: Grid theming tokens (`DT.Grid` NSColors + `DT.monoNSFont`)

**Files:**
- Modify: `Sources/Simpleton/Views/DesignTokens.swift` (add inside `enum DT`, near the existing `Banner` nested enum)

**Interfaces:**
- Consumes: existing `NSColor(hex:)` (`ThemeApplier.swift`); `ThemeSettings.shared.theme.chrome` (`ChromeColors`); `AppTheme` (unused here); `ThemeSettings.shared.monoFontFamily`.
- Produces (all inside `enum DT`):
  - `enum Grid { static var headerBackground: NSColor; static var headerText: NSColor; static var gridline: NSColor; static var rowText: NSColor; static var rowTextSecondary: NSColor; static var nullText: NSColor; static var selectionFill: NSColor }`
  - `static func monoNSFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont`

No headless test (app module; not linked into CoreChecks). Verified by build + lint.

- [ ] **Step 1: Add the tokens**

In `Sources/Simpleton/Views/DesignTokens.swift`, add these members inside `enum DT` (place them after the `Banner` enum). The `ns(_:)` and `chrome` helpers mirror the existing private `c(_:)`/`chrome` pattern in the file:

```swift
    // MARK: - Results grid (AppKit NSTableView)

    /// Themed NSColors for the SQL results grid. They read the same chrome hex
    /// as the SwiftUI tokens (via NSColor(hex:) in ThemeApplier), so the grid
    /// re-themes live when the appearance changes.
    enum Grid {
        private static func ns(_ hex: String) -> NSColor {
            NSColor(hex: hex) ?? NSColor(red: 1, green: 0, blue: 1, alpha: 1)
        }
        private static var chrome: ChromeColors { ThemeSettings.shared.theme.chrome }

        static var headerBackground: NSColor { ns(chrome.surface) }
        static var headerText: NSColor { ns(chrome.textSecondary) }
        static var gridline: NSColor { ns(chrome.border).withAlphaComponent(0.5) }
        static var rowText: NSColor { ns(chrome.textPrimary) }
        static var rowTextSecondary: NSColor { ns(chrome.textSecondary) }
        static var nullText: NSColor { ns(chrome.textFaint) }
        static var selectionFill: NSColor { ns(chrome.selected) }
    }

    /// The configured mono font as an NSFont (tabular digits; matches the
    /// terminal). Falls back to the system monospaced font.
    static func monoNSFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let family = ThemeSettings.shared.monoFontFamily
        if !family.isEmpty, let f = NSFont(name: family, size: size) { return f }
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds clean. (If `ChromeColors` is not already visible in this file, confirm — the existing `private static var chrome: ChromeColors` at the top of `DT` proves it is.)

- [ ] **Step 3: Lint**

Run: `swift format lint --recursive --parallel --strict Sources Tests`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add Sources/Simpleton/Views/DesignTokens.swift
git commit -m "feat(sql): themed NSColor + NSFont tokens for the results grid"
```

---

### Task 4: `SQLDataGrid` — the NSTableView grid engine

**Files:**
- Create: `Sources/Simpleton/Panels/SQL/SQLDataGrid.swift`

**Interfaces:**
- Consumes: `SQLGridData` (Task 2), `SQLCellFormatting`/`CellPresentation` (Task 1), `DT.Grid`/`DT.monoNSFont` (Task 3).
- Produces (used by Task 6):
  - `struct SQLDataGrid: NSViewRepresentable` with initializer arguments `data: SQLGridData`, `sortColumn: Binding<Int?>`, `ascending: Binding<Bool>`, `selectedRow: Binding<Int?>`, `rowHeight: CGFloat`, `onActivateRecord: () -> Void`.
- `selectedRow` is the **original** row index of the focused row (nil when none).

No headless test (AppKit view; its data logic is already covered by `SQLGridData` checks). Verified by build + lint.

- [ ] **Step 1: Write the implementation**

Create `Sources/Simpleton/Panels/SQL/SQLDataGrid.swift`:

```swift
// Sources/Simpleton/Panels/SQL/SQLDataGrid.swift
import AppKit
import SimpletonSQL
import SwiftUI

/// An Excel-like, read-only results grid backed by a view-based NSTableView.
/// Builds columns at runtime from the query result, reuses cell views, sorts
/// in-memory, and copies TSV. The data logic lives in `SQLGridData`.
struct SQLDataGrid: NSViewRepresentable {
    let data: SQLGridData
    @Binding var sortColumn: Int?
    @Binding var ascending: Bool
    @Binding var selectedRow: Int?
    let rowHeight: CGFloat
    var onActivateRecord: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = GridTableView()
        table.coordinator = context.coordinator
        table.usesAlternatingRowBackgroundColors = false
        table.allowsColumnResizing = true
        table.allowsColumnReordering = true
        table.allowsMultipleSelection = true
        table.usesAutomaticRowHeights = false
        table.rowHeight = rowHeight
        table.gridStyleMask = [.solidHorizontalGridLineMask]
        table.headerView = GridHeaderView()
        table.style = .plain
        table.backgroundColor = .clear
        table.dataSource = context.coordinator
        table.delegate = context.coordinator

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear

        context.coordinator.table = table
        context.coordinator.rebuildColumns()
        context.coordinator.applyOrder()
        context.coordinator.applyTheme()
        table.reloadData()
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let table = context.coordinator.table else { return }
        table.rowHeight = rowHeight
        if context.coordinator.needsColumnRebuild() {
            context.coordinator.rebuildColumns()
        }
        context.coordinator.applyOrder()
        context.coordinator.applyTheme()
        table.reloadData()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: SQLDataGrid
        weak var table: NSTableView?
        private(set) var order: [Int] = []
        private var builtColumnCount = -1
        private let cellID = NSUserInterfaceItemIdentifier("gridCell")
        private let rowID = NSUserInterfaceItemIdentifier("gridRow")

        init(_ parent: SQLDataGrid) { self.parent = parent }

        func needsColumnRebuild() -> Bool { builtColumnCount != parent.data.columnCount }

        func rebuildColumns() {
            guard let table else { return }
            for col in table.tableColumns { table.removeTableColumn(col) }
            let gutter = NSTableColumn(identifier: .init("#"))
            gutter.title = ""
            gutter.width = 44
            gutter.minWidth = 32
            gutter.maxWidth = 80
            table.addTableColumn(gutter)
            for i in parent.data.columns.indices {
                let c = NSTableColumn(identifier: .init(String(i)))
                c.title = parent.data.columns[i].name
                c.width = 140
                c.minWidth = 48
                c.sortDescriptorPrototype = NSSortDescriptor(key: String(i), ascending: true)
                table.addTableColumn(c)
            }
            builtColumnCount = parent.data.columnCount
        }

        func applyOrder() {
            order = parent.data.sortedIndex(sortColumn: parent.sortColumn, ascending: parent.ascending)
        }

        func applyTheme() {
            guard let table else { return }
            table.gridColor = DT.Grid.gridline
            table.headerView?.needsDisplay = true
        }

        private var fontSize: CGFloat { max(10, parent.rowHeight * 0.42) }

        // MARK: DataSource
        func numberOfRows(in tableView: NSTableView) -> Int { order.count }

        // MARK: Delegate
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            if let v = tableView.makeView(withIdentifier: rowID, owner: self) as? GridRowView { return v }
            let v = GridRowView()
            v.identifier = rowID
            return v
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let cell = reuseCell(tableView)
            let id = tableColumn?.identifier.rawValue ?? ""
            if id == "#" {
                cell.configureGutter(number: row + 1)
                return cell
            }
            guard let colIndex = Int(id) else { return cell }
            let original = order.indices.contains(row) ? order[row] : row
            cell.configure(with: SQLCellFormatting.present(parent.data.value(row: original, column: colIndex)),
                           font: DT.monoNSFont(size: fontSize))
            return cell
        }

        private func reuseCell(_ tableView: NSTableView) -> GridCellView {
            if let v = tableView.makeView(withIdentifier: cellID, owner: self) as? GridCellView { return v }
            let v = GridCellView()
            v.identifier = cellID
            return v
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let table else { return }
            let r = table.selectedRow
            parent.selectedRow = (r >= 0 && order.indices.contains(r)) ? order[r] : nil
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            if let sd = tableView.sortDescriptors.first, let key = sd.key, let col = Int(key) {
                parent.sortColumn = col
                parent.ascending = sd.ascending
            } else {
                parent.sortColumn = nil
            }
            applyOrder()
            tableView.reloadData()
        }

        func copySelection(withHeader: Bool) {
            guard let table else { return }
            let originals = table.selectedRowIndexes.map { order.indices.contains($0) ? order[$0] : $0 }
            let tsv = parent.data.tsv(rows: originals, withHeader: withHeader)
            guard !tsv.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(tsv, forType: .string)
        }

        func activateRecord() { parent.onActivateRecord() }
    }
}

/// NSTableView subclass: Cmd-C copy, Space -> record mode, and a copy menu.
final class GridTableView: NSTableView {
    weak var coordinator: SQLDataGrid.Coordinator?

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" {
            coordinator?.copySelection(withHeader: false)
            return
        }
        if event.charactersIgnoringModifiers == " " {
            coordinator?.activateRecord()
            return
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        if row >= 0, !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy", action: #selector(copyPlain), keyEquivalent: "")
        menu.addItem(withTitle: "Copy with Column Names", action: #selector(copyWithHeader), keyEquivalent: "")
        for item in menu.items { item.target = self }
        return menu
    }

    @objc private func copyPlain() { coordinator?.copySelection(withHeader: false) }
    @objc private func copyWithHeader() { coordinator?.copySelection(withHeader: true) }
}

/// Row view that themes the selection fill.
final class GridRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        DT.Grid.selectionFill.setFill()
        dirtyRect.fill()
    }
}

/// A reused cell view: one themed, aligned text field.
final class GridCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.cell?.usesSingleLineMode = true
        label.drawsBackground = false
        label.isBordered = false
        label.isEditable = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not implemented") }

    func configure(with p: CellPresentation, font: NSFont) {
        label.font = font
        label.alignment = (p.alignment == .trailing) ? .right : .left
        if p.isNull {
            label.stringValue = "NULL"
            label.textColor = DT.Grid.nullText
        } else if p.isEmptyText {
            label.stringValue = "(empty)"
            label.textColor = DT.Grid.nullText
        } else if p.role == .bool {
            label.stringValue = (p.text == "true") ? "✓" : "✗"
            label.textColor = DT.Grid.rowText
        } else {
            label.stringValue = p.text
            label.textColor = (p.role == .number) ? DT.Grid.rowText : DT.Grid.rowTextSecondary
        }
    }

    func configureGutter(number: Int) {
        label.font = DT.monoNSFont(size: 10)
        label.alignment = .right
        label.stringValue = String(number)
        label.textColor = DT.Grid.nullText
    }
}

/// Fully custom, themed header: fills the background, draws titles + hairline
/// dividers + a sort arrow. Overriding only `draw` preserves the default
/// click-to-sort, resize, and reorder mouse handling.
final class GridHeaderView: NSTableHeaderView {
    override func draw(_ dirtyRect: NSRect) {
        DT.Grid.headerBackground.setFill()
        dirtyRect.fill()
        guard let table = tableView else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: DT.Grid.headerText,
            .font: DT.monoNSFont(size: 10, weight: .semibold),
        ]
        DT.Grid.gridline.setStroke()
        let sort = table.sortDescriptors.first
        for i in table.tableColumns.indices {
            let rect = headerRect(ofColumn: i)
            guard rect.intersects(dirtyRect) else { continue }
            let col = table.tableColumns[i]
            let title = col.title as NSString
            let size = title.size(withAttributes: attrs)
            let textRect = NSRect(x: rect.minX + 6, y: rect.midY - size.height / 2,
                                  width: max(0, rect.width - 24), height: size.height)
            title.draw(in: textRect, withAttributes: attrs)
            if let sd = sort, sd.key == col.identifier.rawValue {
                let arrow = (sd.ascending ? "▲" : "▼") as NSString
                let aSize = arrow.size(withAttributes: attrs)
                arrow.draw(at: NSPoint(x: rect.maxX - aSize.width - 6, y: rect.midY - aSize.height / 2),
                           withAttributes: attrs)
            }
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.maxX - 0.5, y: rect.minY + 3))
            path.line(to: NSPoint(x: rect.maxX - 0.5, y: rect.maxY - 3))
            path.lineWidth = 1
            path.stroke()
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Lint**

Run: `swift format lint --recursive --parallel --strict Sources Tests`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add Sources/Simpleton/Panels/SQL/SQLDataGrid.swift
git commit -m "feat(sql): NSTableView-backed results grid (sort, resize, select, copy, themed)"
```

---

### Task 5: `SQLRecordView` — the record/form mode

**Files:**
- Create: `Sources/Simpleton/Panels/SQL/SQLRecordView.swift`

**Interfaces:**
- Consumes: `Column`, `SQLValue` (SQLDriver.swift); `SQLCellFormatting`/`CellPresentation` (Task 1); `DT.*`, `ThemedDivider` (existing).
- Produces (used by Task 6): `struct SQLRecordView: View` with initializer arguments `columns: [Column]`, `rows: [[SQLValue]]`, `selectedRow: Binding<Int?>`.

No headless test (SwiftUI view). Verified by build + lint.

- [ ] **Step 1: Write the implementation**

Create `Sources/Simpleton/Panels/SQL/SQLRecordView.swift`:

```swift
// Sources/Simpleton/Panels/SQL/SQLRecordView.swift
import SimpletonSQL
import SwiftUI

/// Record mode: one row's fields as label -> value, filtered by field name,
/// with prev/next stepping. Read-only; reuses SQLCellFormatting.
struct SQLRecordView: View {
    let columns: [Column]
    let rows: [[SQLValue]]
    @Binding var selectedRow: Int?
    @State private var filter = ""

    private var rowIndex: Int {
        guard !rows.isEmpty else { return 0 }
        return min(max(selectedRow ?? 0, 0), rows.count - 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ThemedDivider()
            if rows.isEmpty {
                Text("No rows.").font(.system(size: 11)).foregroundColor(DT.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView { fields }
            }
        }
        .onAppear { if selectedRow == nil, !rows.isEmpty { selectedRow = 0 } }
    }

    private var header: some View {
        HStack(spacing: 8) {
            TextField("Filter fields…", text: $filter)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 200)
            Spacer()
            Text("row \(rows.isEmpty ? 0 : rowIndex + 1) of \(rows.count)")
                .font(DT.monoFont(size: 11)).foregroundColor(DT.textTertiary)
            Button { step(-1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.plain).disabled(rowIndex <= 0)
            Button { step(1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.plain).disabled(rows.isEmpty || rowIndex >= rows.count - 1)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { idx, col in
                if filter.isEmpty || col.name.localizedCaseInsensitiveContains(filter) {
                    fieldRow(name: col.name, presentation: SQLCellFormatting.present(cellValue(idx)))
                    ThemedDivider()
                }
            }
        }
    }

    private func fieldRow(name: String, presentation p: CellPresentation) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(name)
                .font(DT.monoFont(size: 11, weight: .semibold))
                .foregroundColor(DT.textSecondary)
                .frame(width: 140, alignment: .leading).lineLimit(1)
            valueText(p)
                .font(DT.monoFont(size: 11))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
    }

    @ViewBuilder private func valueText(_ p: CellPresentation) -> some View {
        if p.isNull {
            Text("NULL").foregroundColor(DT.textFaint)
        } else if p.isEmptyText {
            Text("(empty)").foregroundColor(DT.textFaint)
        } else if p.role == .bool {
            Text(p.text == "true" ? "✓" : "✗").foregroundColor(DT.textPrimary)
        } else {
            Text(p.text).foregroundColor(DT.textPrimary)
        }
    }

    private func cellValue(_ col: Int) -> SQLValue {
        guard rows.indices.contains(rowIndex), rows[rowIndex].indices.contains(col) else { return .null }
        return rows[rowIndex][col]
    }

    private func step(_ delta: Int) {
        guard !rows.isEmpty else { return }
        selectedRow = min(max(rowIndex + delta, 0), rows.count - 1)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Lint**

Run: `swift format lint --recursive --parallel --strict Sources Tests`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add Sources/Simpleton/Panels/SQL/SQLRecordView.swift
git commit -m "feat(sql): record/form mode for a single result row"
```

---

### Task 6: `SQLResultsView` — container + toggle, wired into the panel

**Files:**
- Create: `Sources/Simpleton/Panels/SQL/SQLResultsView.swift`
- Modify: `Sources/Simpleton/Panels/SQL/SQLPanelView.swift:62` (swap `SQLResultsGrid` for `SQLResultsView`)
- Delete: `Sources/Simpleton/Panels/SQL/SQLResultsGrid.swift`

**Interfaces:**
- Consumes: `QueryResult`, `Column`, `SQLValue` (SQLDriver.swift); `SQLGridData` (Task 2); `SQLDataGrid` (Task 4); `SQLRecordView` (Task 5); `DT.*`, `ThemedDivider`, `ThemeSettings` (existing).
- Produces: `struct SQLResultsView: View` taking `result: QueryResult?`; plus top-level `enum ResultsMode` and `enum GridDensity` (in the same file).

No headless test (SwiftUI/AppKit integration). Verified by build + lint + `swift run CoreChecks` (Tasks 1–2 stay green) + `scripts/e2e/sql-e2e.sh`.

- [ ] **Step 1: Write the container**

Create `Sources/Simpleton/Panels/SQL/SQLResultsView.swift`:

```swift
// Sources/Simpleton/Panels/SQL/SQLResultsView.swift
import SimpletonSQL
import SwiftUI

enum ResultsMode: String, CaseIterable, Hashable { case grid = "Grid", record = "Record" }

enum GridDensity: String, CaseIterable {
    case compact, comfortable, spacious
    var rowHeight: CGFloat {
        switch self {
        case .compact: return 22
        case .comfortable: return 28
        case .spacious: return 34
        }
    }
    var label: String { rawValue.capitalized }
}

/// The SQL results area: handles empty/status states and hosts the Grid|Record
/// modes over a `.rows` result. Read-only.
struct SQLResultsView: View {
    let result: QueryResult?
    @State private var mode: ResultsMode = .grid
    @State private var sortColumn: Int?
    @State private var ascending = true
    @State private var selectedRow: Int?
    @AppStorage("sql.grid.density") private var density: GridDensity = .comfortable
    @ObservedObject private var themeSettings = ThemeSettings.shared

    var body: some View {
        switch result {
        case .none:
            hint("Run a query to see results.")
        case .status(let affected, let message):
            statusLine(affected: affected, message: message)
        case .rows(let columns, let rows):
            if rows.isEmpty { hint("No rows.") } else { rowsBody(columns: columns, rows: rows) }
        }
    }

    private func rowsBody(columns: [Column], rows: [[SQLValue]]) -> some View {
        let data = SQLGridData(columns: columns, rows: rows)
        return VStack(spacing: 0) {
            toolbar(rowCount: rows.count)
            ThemedDivider()
            if mode == .grid {
                SQLDataGrid(
                    data: data,
                    sortColumn: $sortColumn,
                    ascending: $ascending,
                    selectedRow: $selectedRow,
                    rowHeight: density.rowHeight,
                    onActivateRecord: { mode = .record }
                )
            } else {
                SQLRecordView(columns: columns, rows: rows, selectedRow: $selectedRow)
            }
        }
        .onExitCommand { if mode == .record { mode = .grid } }
    }

    private func toolbar(rowCount: Int) -> some View {
        HStack(spacing: 8) {
            Picker("", selection: $mode) {
                ForEach(ResultsMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Spacer()
            Text("\(rowCount) row\(rowCount == 1 ? "" : "s")")
                .font(DT.monoFont(size: 11)).foregroundColor(DT.textTertiary)
            Menu {
                ForEach(GridDensity.allCases, id: \.self) { d in
                    Button(d.label) { density = d }
                }
            } label: {
                Image(systemName: "arrow.up.and.down.text.horizontal")
            }
            .menuStyle(.borderlessButton).fixedSize().help("Row density")
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
    }

    private func statusLine(affected: Int, message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle").foregroundColor(DT.accentGreen)
            Text("\(affected) row\(affected == 1 ? "" : "s") affected — \(message)")
                .font(DT.monoFont(size: 11)).foregroundColor(DT.textSecondary)
            Spacer()
        }.padding(8)
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundColor(DT.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 2: Swap the call site**

In `Sources/Simpleton/Panels/SQL/SQLPanelView.swift`, change line 62 from:

```swift
            SQLResultsGrid(result: model.result)
```

to:

```swift
            SQLResultsView(result: model.result)
```

- [ ] **Step 3: Delete the old grid**

```bash
git rm Sources/Simpleton/Panels/SQL/SQLResultsGrid.swift
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: builds clean; no remaining reference to `SQLResultsGrid`.

- [ ] **Step 5: Full verification**

Run:
```bash
swift run CoreChecks
swift format lint --recursive --parallel --strict Sources Tests
scripts/e2e/sql-e2e.sh
```
Expected: CoreChecks all pass (incl. the new `SQLCellFormatting`/`SQLGridData` suites); lint clean; `sql-e2e.sh` prints `sql e2e: PASS`.

- [ ] **Step 6: Commit**

```bash
git add Sources/Simpleton/Panels/SQL/SQLResultsView.swift Sources/Simpleton/Panels/SQL/SQLPanelView.swift
git commit -m "feat(sql): results view with Grid|Record toggle, density, wired into the SQL panel"
```

---

## Self-Review

**Spec coverage:**
- Two modes behind a segmented toggle → Task 6 (`ResultsMode`, `SQLResultsView`) + Tasks 4/5. ✓
- Type-aware rendering (numbers trailing/tabular, NULL/EMPTY tokens, bool glyphs, blob) → Task 1 (`present`) + Tasks 4/5 rendering. ✓
- In-memory sort, NULLs last ascending, stable → Task 1 (`compare`) + Task 2 (`sortedIndex`). ✓
- Row-number gutter, resize/reorder, sticky themed header + sort arrow → Task 4. ✓
- Multi-row selection + NULL-preserving TSV copy (RFC-4180 quoting) + copy menu → Task 2 (`tsv`) + Task 4 (`copySelection`, menu). ✓
- Record mode: label→value, field filter, prev/next, Space-to-record / Esc-to-grid → Task 5 + Task 6 (`onActivateRecord`, `onExitCommand`). ✓
- Density presets persisted → Task 6 (`GridDensity` + `@AppStorage`). ✓
- Live theming, no background so themedGlass shows through → Task 3 tokens + Task 4 (`drawsBackground = false`, `applyTheme`) + Task 6 (`@ObservedObject ThemeSettings`). ✓
- Pure logic in SimpletonSQL, headless CoreChecks → Tasks 1–2. ✓
- Delete old grid, keep `.status`/empty rendering → Task 6. ✓
- Non-goals (editing, cell-range, frozen column, multi-sort, width persistence) → not implemented, by design. ✓

**Placeholder scan:** none — every step carries real code or an exact command.

**Type consistency:** `CellPresentation`/`CellRole`/`CellAlignment` (Task 1) are used verbatim in Tasks 2/4/5. `SQLGridData(columns:rows:)`, `sortedIndex(sortColumn:ascending:)`, `value(row:column:)`, `tsv(rows:withHeader:)` (Task 2) match their uses in Task 4. `DT.Grid.*` and `DT.monoNSFont(size:weight:)` (Task 3) match Task 4/6 uses. `SQLDataGrid` init args (Task 4) match the call in Task 6. `SQLRecordView(columns:rows:selectedRow:)` (Task 5) matches Task 6. `SQLResultsView(result:)` (Task 6) matches the `SQLPanelView.swift:62` call site. ✓
