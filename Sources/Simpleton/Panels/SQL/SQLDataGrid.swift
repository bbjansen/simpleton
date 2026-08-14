// Sources/Simpleton/Panels/SQL/SQLDataGrid.swift
import AppKit
import SimpletonSQL
import SwiftUI

/// An Excel-like results grid backed by a view-based NSTableView. Builds columns at runtime from the
/// query result, reuses cell views, sorts in-memory, and copies TSV. Read-only unless `editable` is
/// set, in which case double-clicking a cell edits it (staged, tinted). The data logic lives in
/// `SQLGridData`.
struct SQLDataGrid: NSViewRepresentable {
    let data: SQLGridData
    @Binding var sortKeys: [SortKey]
    @Binding var selectedRow: Int?
    /// The current display page over the sorted order. The grid shows only `order[start..<end]`;
    /// selection and staged edits still live in original-row space so they survive paging.
    let page: PageBounds
    let rowHeight: CGFloat
    /// Non-nil when this result can be edited in place (drives the double-click = edit gesture and
    /// the "Set NULL" menu item). Read-only when nil.
    let editable: EditableTarget?
    /// Navigable FK cells keyed by result-column index. A right-click on a cell in one of these
    /// columns (unless NULL) offers "Go to <referencedTable>".
    let foreignKeyMatches: [Int: SQLForeignKeyMatcher.Match]
    /// Staged (uncommitted) edits keyed by original-row/column. The grid renders these tinted and
    /// prefers them over the underlying value.
    @Binding var stagedEdits: [CellCoord: SQLValue]
    var onActivateRecord: () -> Void
    /// "Inspect Value…" — always available (right-click), and the double-click action when read-only.
    var onInspect: (Int, Int) -> Void
    /// "Go to <referencedTable>" — jump from an FK cell (original row, result-column index) to the
    /// referenced row. Only wired when the column is an FK and the cell is non-NULL.
    var onNavigateForeignKey: (Int, Int) -> Void

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
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.cellDoubleClicked(_:))

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear

        // A click-through overlay pinned over the table draws the rubber-band cell rectangle. It
        // returns nil from hitTest so every click/double-click still reaches the cells beneath it.
        let overlay = CellSelectionOverlay()
        overlay.coordinator = context.coordinator
        overlay.frame = table.bounds
        overlay.autoresizingMask = [.width, .height]
        table.addSubview(overlay)
        context.coordinator.overlay = overlay
        table.selectionOverlay = overlay

        context.coordinator.table = table
        context.coordinator.scrollView = scroll
        context.coordinator.observeColumnLayout()
        context.coordinator.installFrozenGutter()
        context.coordinator.rebuildColumns()
        context.coordinator.applyOrder()
        context.coordinator.applyTheme()
        context.coordinator.reloadPreservingSelection()
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
        context.coordinator.reloadPreservingSelection()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: SQLDataGrid
        weak var table: NSTableView?
        weak var scrollView: NSScrollView?
        /// The left-pinned frozen pane: a single manually-drawn view (floated on the horizontal axis so
        /// it stays put during horizontal scroll while AppKit scrolls it vertically in lockstep with the
        /// rows). It draws the row-number gutter AND the first data column's cells, reading the main
        /// table's own row rects for alignment and the shared `SQLGridData.cellStyle` for content — so a
        /// single mini `NSTableView` (which AppKit refused to paint reliably inside a floating scroll
        /// view) is avoided while the cell configuration still comes from the ONE shared path.
        private var frozenPane: FrozenColumnView?
        private var scrollObserver: NSObjectProtocol?
        /// Fires when the main scroll view resizes, so the frozen pane re-fits to the new height.
        private var sizeObserver: NSObjectProtocol?
        /// Width of the frozen row-number gutter strip; matches the old "#" column width.
        private let gutterWidth: CGFloat = 44
        /// The data-column index currently frozen (rendered in the frozen pane, hidden in the main
        /// table). It's whatever sits at view position 0 — the leftmost column — so it tracks column
        /// reordering. `nil` before columns are built.
        private(set) var frozenColumnIndex: Int?
        /// The width of the frozen data column in the pane. Seeded from a default / persisted value and
        /// updated when the user drags the pane's column divider.
        var frozenColumnStoredWidth: CGFloat = 160
        /// Original row indices shown on the current page, in display (sorted) order. This is the
        /// per-page slice of the full sorted order; all row math for the visible table uses this.
        private(set) var order: [Int] = []
        /// The current rectangular cell selection in display space (display rows × table-column view
        /// positions), or nil when only whole rows are selected. Drawn by `CellSelectionOverlay` and
        /// copied as rectangular TSV on ⌘C. Kept separate from NSTableView's row selection so record
        /// mode and inline editing keep using the row selection unchanged.
        private(set) var cellSelection: CellSelection?
        /// The sort + page state the current `order` was built from. Used to drop the rectangular cell
        /// selection only when the order actually changes, not on every unrelated update pass.
        private var lastOrderStamp: SelectionStamp?
        private var builtColumns: [Column] = []
        private var enumCols: Set<Int> = []
        private var isProgrammaticReload = false
        private var isApplyingSort = false
        private var isRestoringLayout = false
        private var resizeObserver: NSObjectProtocol?
        private var moveObserver: NSObjectProtocol?
        private let cellID = NSUserInterfaceItemIdentifier("gridCell")
        private let rowID = NSUserInterfaceItemIdentifier("gridRow")

        init(_ parent: SQLDataGrid) { self.parent = parent }

        deinit {
            let observers = [resizeObserver, moveObserver, scrollObserver, sizeObserver]
            for obs in observers.compactMap({ $0 }) { NotificationCenter.default.removeObserver(obs) }
        }

        /// Persist a column's width + order (keyed by stable identifier) whenever the user resizes or
        /// reorders, so the layout survives switching between queries with the same columns.
        func observeColumnLayout() {
            guard let table else { return }
            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSTableView.columnDidResizeNotification, object: table, queue: .main
            ) { [weak self] _ in self?.saveColumnWidths() }
            moveObserver = NotificationCenter.default.addObserver(
                forName: NSTableView.columnDidMoveNotification, object: table, queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.saveColumnOrder()
                // A reorder can change which column is leftmost; re-freeze it into the pane.
                self.refreshFrozenColumns()
                self.refreshFrozenGutter()
            }
        }

        /// The stable identifier of the currently-frozen column, or nil. Persisted-width/order code
        /// skips it because the main table keeps it collapsed to zero width (the pane renders it).
        private var frozenColumnID: String? { frozenColumnIndex.map(String.init) }

        private func widthsKey() -> String { "sql.grid.widths.\(parent.data.columnSignature)" }
        private func orderKey() -> String { "sql.grid.order.\(parent.data.columnSignature)" }
        /// The frozen data column's width is persisted under its own key — NOT the shared main widths
        /// dict — because the main copy is collapsed to 0 and the pane owns the real width.
        private func frozenWidthsKey() -> String { "sql.grid.frozenwidths.\(parent.data.columnSignature)" }

        func saveColumnWidths() {
            guard !isRestoringLayout, let table else { return }
            var widths: [String: Double] = [:]
            // Skip the gutter and the frozen column (collapsed to 0 in the main table — its real width
            // is persisted separately under the frozen-widths key).
            for col in table.tableColumns
            where col.identifier.rawValue != "#" && col.identifier.rawValue != frozenColumnID {
                widths[col.identifier.rawValue] = Double(col.width)
            }
            UserDefaults.standard.set(widths, forKey: widthsKey())
            // Persist the frozen column's user-set width under its own key + column id.
            if let id = frozenColumnID {
                var frozen = UserDefaults.standard.dictionary(forKey: frozenWidthsKey()) as? [String: Double] ?? [:]
                frozen[id] = Double(frozenColumnStoredWidth)
                UserDefaults.standard.set(frozen, forKey: frozenWidthsKey())
            }
        }

        func restoreColumnWidths() {
            guard let table,
                let saved = UserDefaults.standard.dictionary(forKey: widthsKey()) as? [String: Double]
            else { return }
            isRestoringLayout = true
            defer { isRestoringLayout = false }
            // Never restore the frozen column here (it's collapsed to 0); its width comes from the
            // frozen-widths key in `refreshFrozenColumns`.
            for col in table.tableColumns
            where col.identifier.rawValue != "#" && col.identifier.rawValue != frozenColumnID {
                if let w = saved[col.identifier.rawValue] { col.width = CGFloat(w) }
            }
        }

        func saveColumnOrder() {
            guard !isRestoringLayout, let table else { return }
            let order = table.tableColumns.map(\.identifier.rawValue).filter { $0 != "#" }
            UserDefaults.standard.set(order, forKey: orderKey())
        }

        func restoreColumnOrder() {
            guard let table, let saved = UserDefaults.standard.array(forKey: orderKey()) as? [String] else { return }
            isRestoringLayout = true
            defer { isRestoringLayout = false }
            // Move each saved identifier into its position. Data columns start at index 0 now that the
            // gutter is a floating view rather than table column 0. Stale "#" entries are ignored.
            for (target, id) in saved.filter({ $0 != "#" }).enumerated() {
                guard target < table.tableColumns.count,
                    let from = table.tableColumns.firstIndex(where: { $0.identifier.rawValue == id }),
                    from != target
                else { continue }
                table.moveColumn(from, toColumn: target)
            }
        }

        /// Rebuild when the column identity changes — not merely the count, or a
        /// new query with the same column count keeps the previous headers.
        func needsColumnRebuild() -> Bool { builtColumns != parent.data.columns }

        func rebuildColumns() {
            guard let table else { return }
            // A fresh column set: forget the previously-frozen column so refreshFrozenColumns re-picks
            // the new leftmost one (the old index may not exist in the new result).
            frozenColumnIndex = nil
            for col in table.tableColumns { table.removeTableColumn(col) }
            // The row-number gutter is not a main-table column — it lives in the frozen pane, along with
            // the first data column. Main data columns start at view position 0.
            for i in parent.data.columns.indices {
                let c = NSTableColumn(identifier: .init(String(i)))
                c.title = parent.data.columns[i].name
                c.width = 140
                c.minWidth = 48
                c.sortDescriptorPrototype = NSSortDescriptor(key: String(i), ascending: true)
                table.addTableColumn(c)
            }
            builtColumns = parent.data.columns
            enumCols = parent.data.enumColumns()
            restoreColumnWidths()
            restoreColumnOrder()
            // Freeze the leftmost data column into the pane (hides it in the main table) and reload.
            refreshFrozenColumns()
            refreshFrozenGutter()
        }

        func applyOrder() {
            let full = parent.data.sortedIndex(by: parent.sortKeys)
            // Slice the sorted order to the current page window. Bounds are already clamped by
            // SQLPaging, but guard against a stale binding pass that hasn't re-derived the page yet.
            let start = min(max(parent.page.start, 0), full.count)
            let end = min(max(parent.page.end, start), full.count)
            order = Array(full[start..<end])
            // A rectangular cell selection is display-row addressed, so it stops being meaningful once
            // the order changes (new sort or a different page). Drop it then — but not on the many
            // update passes where sort + page are unchanged (e.g. a plain row-selection change).
            let stamp = SelectionStamp(sortKeys: parent.sortKeys, start: parent.page.start, end: parent.page.end)
            if stamp != lastOrderStamp {
                lastOrderStamp = stamp
                if cellSelection != nil { cellSelection = nil }
            }
        }

        func applyTheme() {
            guard let table else { return }
            table.gridColor = DT.Grid.gridline
            table.headerView?.needsDisplay = true
            frozenPane?.needsDisplay = true
        }

        // MARK: Frozen pane (row-number gutter + first data column)

        /// Install the left-pinned frozen pane: a single manually-drawn `FrozenColumnView`, floated on
        /// the horizontal axis so it stays put during horizontal scroll while AppKit scrolls it
        /// vertically in lockstep with the rows (the exact mechanism the original gutter used, which is
        /// why it aligns reliably). It draws the gutter numbers + the first data column's cells by
        /// reading the main table's own row rects and the shared `SQLGridData.cellStyle`. A matching
        /// left content inset keeps the main columns from rendering under the pane.
        func installFrozenGutter() {
            guard let scrollView, frozenPane == nil else { return }
            scrollView.automaticallyAdjustsContentInsets = false

            let pane = FrozenColumnView()
            pane.coordinator = self
            pane.autoresizingMask = [.height]
            frozenPane = pane
            scrollView.addFloatingSubview(pane, for: .horizontal)

            let clip = scrollView.contentView
            clip.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
            ) { [weak self] _ in self?.refreshFrozenGutter() }
            // Re-layout the pane whenever the scroll view resizes — its final height often isn't known
            // until after the SwiftUI mount, so the pane must re-fit or it stays stranded at 0 height.
            scrollView.postsFrameChangedNotifications = true
            sizeObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification, object: scrollView, queue: .main
            ) { [weak self] _ in self?.layoutFrozenPane() }

            layoutFrozenPane()
        }

        /// Size the frozen pane to `gutter + frozenColumnStoredWidth` and set the matching left content
        /// inset on the main scroll view so the main columns start just right of the pane. A
        /// `.horizontal` floating subview is positioned inside the (left-inset) content area, so a naive
        /// (0,0) frame lands offset by the inset; map the scroll view's whole bounds into the pane's
        /// superview space (handles the flip) and take its left `paneWidth` slice so the pane overlays
        /// the grid's true left edge, full height.
        func layoutFrozenPane() {
            guard let scrollView, let pane = frozenPane else { return }
            let paneWidth = FrozenColumnGeometry.paneWidth(
                gutter: gutterWidth, frozenColumnWidth: frozenColumnStoredWidth)
            scrollView.contentInsets = NSEdgeInsets(top: 0, left: paneWidth, bottom: 0, right: 0)
            if let superview = pane.superview {
                let full = superview.convert(scrollView.bounds, from: scrollView)
                pane.frame = NSRect(x: full.minX, y: full.minY, width: paneWidth, height: full.height)
            } else {
                pane.frame = NSRect(x: 0, y: 0, width: paneWidth, height: scrollView.bounds.height)
            }
            pane.needsDisplay = true
        }

        /// Adopt a new frozen data column (whatever sits at view position 0 — the leftmost column), so
        /// the frozen pane tracks column reordering. The main table keeps the column collapsed to zero
        /// width (its cells live in the pane), but not removed, so ordering/identity/copy-mapping are
        /// unchanged. Called from `rebuildColumns` and after a column move.
        func refreshFrozenColumns() {
            guard let table else { return }
            // Restore any previously-frozen main column to a usable width before re-freezing another.
            if let index = frozenColumnIndex,
                let prev = table.tableColumns.first(where: { $0.identifier.rawValue == String(index) })
            {
                prev.minWidth = 48
                if prev.width < 1 { prev.width = frozenColumnStoredWidth }
            }
            guard let leftmost = table.tableColumns.first, let dataIndex = Int(leftmost.identifier.rawValue)
            else {
                frozenColumnIndex = nil
                return
            }
            frozenColumnIndex = dataIndex
            // Seed the pane column width from the persisted frozen width for this column, else a default.
            let saved = UserDefaults.standard.dictionary(forKey: frozenWidthsKey()) as? [String: Double]
            frozenColumnStoredWidth = max(48, saved?[String(dataIndex)].map { CGFloat($0) } ?? 160)
            // Collapse the frozen column in the main table (minWidth first, else width clamps back up).
            leftmost.minWidth = 0
            leftmost.width = 0
            layoutFrozenPane()
        }

        /// The header title for the frozen data column (drawn by the pane), read from the main table.
        func frozenColumnTitle() -> String {
            guard let table, let index = frozenColumnIndex,
                let col = table.tableColumns.first(where: { $0.identifier.rawValue == String(index) })
            else { return "" }
            return col.title
        }

        /// Redraw the frozen pane after the row set changes (reload, sort, page, resize) — it reads the
        /// main table's live geometry, so a redraw is all it needs to re-align.
        func refreshFrozenGutter() {
            frozenPane?.endFrozenEditing(commit: true)
            layoutFrozenPane()
            frozenPane?.needsDisplay = true
        }

        /// Persist the frozen data column's width (under the frozen-widths key) after a divider drag.
        func saveFrozenColumnWidth() {
            guard let id = frozenColumnIndex.map(String.init) else { return }
            var frozen = UserDefaults.standard.dictionary(forKey: frozenWidthsKey()) as? [String: Double] ?? [:]
            frozen[id] = Double(frozenColumnStoredWidth)
            UserDefaults.standard.set(frozen, forKey: frozenWidthsKey())
        }

        /// Absolute (paged) 1-based row number for a display row — what the gutter draws.
        func rowNumber(forDisplayRow row: Int) -> Int { parent.page.start + row + 1 }

        var frozenGutterWidth: CGFloat { gutterWidth }
        var frozenFontSize: CGFloat { fontSize }
        var frozenEnumColumns: Set<Int> { enumCols }

        /// Reload and restore the table selection from the `selectedRow` binding
        /// (mapping the original row index back to its current display row). The
        /// `isProgrammaticReload` guard stops selection callbacks from writing
        /// SwiftUI state during the view-update pass.
        func reloadPreservingSelection() {
            guard let table else { return }
            isProgrammaticReload = true
            table.reloadData()
            if let sel = parent.selectedRow, let displayRow = order.firstIndex(of: sel) {
                table.selectRowIndexes(IndexSet(integer: displayRow), byExtendingSelection: false)
            } else {
                table.deselectAll(nil)
            }
            isProgrammaticReload = false
            // reloadData re-inserts row views; keep the selection overlay on top and up to date.
            if let overlay {
                overlay.removeFromSuperview()
                overlay.frame = table.bounds
                table.addSubview(overlay)
                overlay.needsDisplay = true
            }
            refreshFrozenGutter()
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
            // The frozen pane owns a row-number gutter column ("#"); the main table does not.
            if id == "#" {
                cell.coordinator = self
                cell.coord = nil
                cell.isEditable = false
                cell.configureGutter(number: rowNumber(forDisplayRow: row))
                return cell
            }
            guard let colIndex = Int(id) else { return cell }
            let original = order.indices.contains(row) ? order[row] : row
            configureCell(cell, original: original, column: colIndex)
            return cell
        }

        /// Configure a reused `GridCellView` for the cell at (original row, data-column). This is the
        /// ONE cell-configuration path — the main table and the frozen first-column pane both call it,
        /// so pills, staged-edit tint, alignment, and fonts stay identical and in sync. The render
        /// instructions come from `SQLGridData.cellStyle` (pure); this only maps the palette slot to a
        /// theme color and sets the edit target on the cell.
        func configureCell(_ cell: GridCellView, original: Int, column colIndex: Int) {
            let coord = CellCoord(row: original, column: colIndex)
            let style = parent.data.cellStyle(
                row: original, column: colIndex, stagedValue: parent.stagedEdits[coord],
                enumColumns: enumCols, enumSlots: DT.Grid.enumPalette.count)
            cell.coordinator = self
            cell.coord = coord
            cell.isEditable = parent.editable != nil
            var enumColor: NSColor?
            if let slot = style.enumSlot {
                let palette = DT.Grid.enumPalette
                if palette.indices.contains(slot) { enumColor = palette[slot] }
            }
            cell.configure(with: style, font: DT.monoNSFont(size: fontSize), enumColor: enumColor)
        }

        /// Stage a parsed edit for the cell at `coord` (or clear it back to the original value when
        /// the typed text re-parses to the same value). Writes through the SwiftUI binding.
        func stageEdit(_ coord: CellCoord, typed text: String) -> Bool {
            let original = parent.data.value(row: coord.row, column: coord.column)
            let base = parent.stagedEdits[coord] ?? original
            guard let parsed = SQLCellEditing.parse(text, like: base) else { return false }
            var edits = parent.stagedEdits
            // If the new value equals the committed value, drop the staged edit entirely.
            if parsed == original {
                edits.removeValue(forKey: coord)
            } else {
                edits[coord] = parsed
            }
            parent.stagedEdits = edits
            reloadPreservingSelection()
            return true
        }

        /// Stage an explicit NULL for the cell (right-click → Set NULL). Only meaningful when editable.
        func stageNull(_ coord: CellCoord) {
            guard parent.editable != nil else { return }
            let original = parent.data.value(row: coord.row, column: coord.column)
            var edits = parent.stagedEdits
            if case .null = original {
                edits.removeValue(forKey: coord)
            } else {
                edits[coord] = .null
            }
            parent.stagedEdits = edits
            reloadPreservingSelection()
        }

        private func reuseCell(_ tableView: NSTableView) -> GridCellView {
            if let v = tableView.makeView(withIdentifier: cellID, owner: self) as? GridCellView { return v }
            let v = GridCellView()
            v.identifier = cellID
            return v
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isProgrammaticReload, let table else { return }
            let r = table.selectedRow
            let newValue = (r >= 0 && order.indices.contains(r)) ? order[r] : nil
            if parent.selectedRow != newValue { parent.selectedRow = newValue }
            // The frozen pane draws the selection band by reading the main table's selection, so a
            // redraw keeps it in sync (rows highlight identically across the frozen boundary).
            frozenPane?.needsDisplay = true
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !isApplyingSort else { return }
            guard let sd = tableView.sortDescriptors.first, let key = sd.key, let col = Int(key) else {
                parent.sortKeys = []
                return
            }
            // Plain click cycles the primary asc → desc → cleared. ⌥-click builds a multi-column
            // sort: add the column as a secondary key, then cycle that key asc → desc → removed.
            let option = NSApp.currentEvent?.modifierFlags.contains(.option) ?? false
            var keys = parent.sortKeys
            if option {
                if let idx = keys.firstIndex(where: { $0.column == col }) {
                    if keys[idx].ascending {
                        keys[idx] = SortKey(column: col, ascending: false)
                    } else {
                        keys.remove(at: idx)
                    }
                } else {
                    keys.append(SortKey(column: col, ascending: true))
                }
            } else if keys.count == 1, keys[0].column == col {
                keys = keys[0].ascending ? [SortKey(column: col, ascending: false)] : []
            } else {
                keys = [SortKey(column: col, ascending: true)]
            }
            // Reflect the full key list back onto the table so the header shows every sorted column
            // (guarded so this programmatic set does not re-enter). The binding change re-runs
            // updateNSView, which re-orders, reloads, and redraws the frozen pane.
            isApplyingSort = true
            tableView.sortDescriptors = keys.map { NSSortDescriptor(key: String($0.column), ascending: $0.ascending) }
            isApplyingSort = false
            parent.sortKeys = keys
        }

        /// ⌘C / Copy: when a rectangular cell selection is active, copy that rectangle as TSV (display
        /// rows → original rows, column view-positions → data-column indices). Otherwise copy the
        /// selected whole rows — the existing behavior, unchanged.
        func copySelection(withHeader: Bool) {
            guard let table else { return }
            if let sel = cellSelection {
                let originals = sel.displayRows.compactMap { order.indices.contains($0) ? order[$0] : nil }
                let columns = dataColumnIndices(forViewPositions: sel.columnPositions)
                let tsv = parent.data.tsv(rows: originals, columns: columns, withHeader: withHeader)
                writeToPasteboard(tsv)
                return
            }
            let originals = table.selectedRowIndexes.map { order.indices.contains($0) ? order[$0] : $0 }
            let tsv = parent.data.tsv(rows: originals, withHeader: withHeader)
            writeToPasteboard(tsv)
        }

        private func writeToPasteboard(_ tsv: String) {
            guard !tsv.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(tsv, forType: .string)
        }

        /// Map an ordered list of table-column view positions to data-column indices (the `Int` in each
        /// column identifier). Reflects the user's current column order.
        private func dataColumnIndices(forViewPositions positions: [Int]) -> [Int] {
            guard let table else { return [] }
            return positions.compactMap { pos in
                guard table.tableColumns.indices.contains(pos) else { return nil }
                return Int(table.tableColumns[pos].identifier.rawValue)
            }
        }

        // MARK: Rectangular cell selection

        /// Begin a rectangular selection at a data cell (display row, table-column view position).
        /// Ignores the gutter. Clears any prior rectangle.
        func beginCellSelection(displayRow row: Int, columnPosition col: Int) {
            guard isDataColumn(col), order.indices.contains(row) else {
                clearCellSelection()
                return
            }
            cellSelection = CellSelection(anchorRow: row, anchorCol: col, extentRow: row, extentCol: col)
            redrawSelection()
        }

        /// Extend the active rectangle to a data cell (drag or shift-click). No-op if no anchor yet or
        /// the target is the gutter.
        func extendCellSelection(displayRow row: Int, columnPosition col: Int) {
            guard var sel = cellSelection, isDataColumn(col), order.indices.contains(row) else { return }
            sel.extentRow = row
            sel.extentCol = col
            cellSelection = sel
            redrawSelection()
        }

        /// Drop the rectangular selection (single click, gutter click, sort/page/edit).
        func clearCellSelection() {
            guard cellSelection != nil else { return }
            cellSelection = nil
            redrawSelection()
        }

        private func isDataColumn(_ position: Int) -> Bool {
            guard let table, table.tableColumns.indices.contains(position) else { return false }
            return table.tableColumns[position].identifier.rawValue != "#"
        }

        /// The click-through overlay that draws the rubber-band rectangle over the table.
        weak var overlay: CellSelectionOverlay?

        /// Mark the overlay for redraw after the rectangle changes.
        private func redrawSelection() { overlay?.needsDisplay = true }

        /// The union rect (in the table's flipped coordinate space) of the current cell selection, or
        /// nil when there's no rectangle. Built from the two corner cells so column reordering and
        /// variable widths are handled by AppKit's own cell frames.
        func selectionRect() -> NSRect? {
            guard let table, let sel = cellSelection,
                order.indices.contains(sel.minRow), order.indices.contains(sel.maxRow),
                table.tableColumns.indices.contains(sel.minCol), table.tableColumns.indices.contains(sel.maxCol)
            else { return nil }
            let topLeft = table.frameOfCell(atColumn: sel.minCol, row: sel.minRow)
            let bottomRight = table.frameOfCell(atColumn: sel.maxCol, row: sel.maxRow)
            guard topLeft != .zero, bottomRight != .zero else { return nil }
            return topLeft.union(bottomRight)
        }

        func activateRecord() { parent.onActivateRecord() }

        /// Double-click a data cell in the MAIN table → edit it (when editable) or inspect it (read
        /// only). The frozen pane handles its own double-click internally (it isn't an NSTableView).
        @objc func cellDoubleClicked(_ sender: NSTableView) {
            let r = sender.clickedRow
            let c = sender.clickedColumn
            guard r >= 0, c >= 0, sender.tableColumns.indices.contains(c),
                let colIndex = Int(sender.tableColumns[c].identifier.rawValue)
            else { return }
            let original = order.indices.contains(r) ? order[r] : r
            if parent.editable != nil {
                beginEditing(displayRow: r, column: c)
            } else {
                parent.onInspect(original, colIndex)
            }
        }

        // MARK: Frozen-pane action bridges (the pane maps its clicks to original row + frozen column)

        /// Whether the current result is editable (drives the pane's double-click = edit gesture).
        var isEditable: Bool { parent.editable != nil }
        /// Inspect the frozen cell for a display row (right-click / read-only double-click in the pane).
        func inspectFrozen(displayRow r: Int) {
            guard let index = frozenColumnIndex, order.indices.contains(r) else { return }
            parent.onInspect(order[r], index)
        }
        /// Stage NULL on the frozen cell for a display row (right-click, editable).
        func setNullFrozen(displayRow r: Int) {
            guard let index = frozenColumnIndex, order.indices.contains(r) else { return }
            stageNull(CellCoord(row: order[r], column: index))
        }
        /// The FK match for the frozen column, if it is a foreign key.
        func frozenForeignKeyMatch() -> SQLForeignKeyMatcher.Match? {
            guard let index = frozenColumnIndex else { return nil }
            return parent.foreignKeyMatches[index]
        }
        /// The (possibly staged) value of the frozen cell for a display row — gates FK nav on non-NULL.
        func frozenCellValue(displayRow r: Int) -> SQLValue? {
            guard let index = frozenColumnIndex, order.indices.contains(r) else { return nil }
            let original = order[r]
            return parent.stagedEdits[CellCoord(row: original, column: index)]
                ?? parent.data.value(row: original, column: index)
        }
        /// Navigate the frozen FK cell for a display row (right-click "Go to …").
        func navigateForeignKeyFrozen(displayRow r: Int) {
            guard let index = frozenColumnIndex, order.indices.contains(r) else { return }
            parent.onNavigateForeignKey(order[r], index)
        }
        /// Select the whole row under a frozen-pane click so ⌘C copies the row; ⇧ extends.
        func selectRowFromFrozen(displayRow r: Int, extending: Bool) {
            guard let table, order.indices.contains(r) else { return }
            clearCellSelection()
            table.selectRowIndexes(IndexSet(integer: r), byExtendingSelection: extending)
        }
        /// Stage a typed edit for the frozen cell (Enter in the pane's inline editor).
        func stageFrozenEdit(displayRow r: Int, typed text: String) -> Bool {
            guard let index = frozenColumnIndex, order.indices.contains(r) else { return false }
            return stageEdit(CellCoord(row: order[r], column: index), typed: text)
        }
        /// The current (committed or staged) value of the frozen cell, seeded into the inline editor.
        func frozenEditingText(displayRow r: Int) -> String {
            guard let index = frozenColumnIndex, order.indices.contains(r) else { return "" }
            let coord = CellCoord(row: order[r], column: index)
            let value = parent.stagedEdits[coord] ?? parent.data.value(row: order[r], column: index)
            return SQLCellEditing.editingText(for: value)
        }
        /// Copy the frozen cell (a single-cell rectangle) or the selected rows — routes through the
        /// existing selection copy after anchoring a 1×1 rectangle on the frozen column (view pos 0).
        func copyFromFrozen(displayRow r: Int, withHeader: Bool) {
            beginCellSelection(displayRow: r, columnPosition: 0)
            copySelection(withHeader: withHeader)
        }

        /// Right-click → Inspect the clicked cell's value (always available, both modes).
        func inspectClicked(displayRow r: Int, column c: Int) {
            guard let table, r >= 0, c >= 0, table.tableColumns.indices.contains(c),
                let colIndex = Int(table.tableColumns[c].identifier.rawValue)
            else { return }
            let original = order.indices.contains(r) ? order[r] : r
            parent.onInspect(original, colIndex)
        }

        /// Right-click → Set NULL on the clicked cell (editable only).
        func setNullClicked(displayRow r: Int, column c: Int) {
            guard let table, r >= 0, c >= 0, table.tableColumns.indices.contains(c),
                let colIndex = Int(table.tableColumns[c].identifier.rawValue)
            else { return }
            let original = order.indices.contains(r) ? order[r] : r
            stageNull(CellCoord(row: original, column: colIndex))
        }

        /// The FK jump available on the cell at a table-column view position, or nil if that column is
        /// not a foreign key. Resolves the view position to the underlying data-column index first, so
        /// it stays correct after the user reorders columns.
        func foreignKeyMatch(forColumnPosition c: Int) -> SQLForeignKeyMatcher.Match? {
            guard let table, table.tableColumns.indices.contains(c),
                let colIndex = Int(table.tableColumns[c].identifier.rawValue)
            else { return nil }
            return parent.foreignKeyMatches[colIndex]
        }

        /// The value shown in the cell at (displayRow, column view-position), preferring any staged
        /// edit — the same value FK navigation filters by. Used to gate the "Go to …" menu item so it
        /// hides on NULL (nothing to match).
        func cellValue(displayRow r: Int, columnPosition c: Int) -> SQLValue? {
            guard let table, order.indices.contains(r), table.tableColumns.indices.contains(c),
                let colIndex = Int(table.tableColumns[c].identifier.rawValue)
            else { return nil }
            let original = order[r]
            return parent.stagedEdits[CellCoord(row: original, column: colIndex)]
                ?? parent.data.value(row: original, column: colIndex)
        }

        /// Right-click → "Go to <referencedTable>": navigate the FK cell at (displayRow, column). Maps
        /// the view position to the data-column index and hands the original row + column to the
        /// callback, which reads the (possibly staged) value and runs the parameterized lookup.
        func navigateForeignKeyClicked(displayRow r: Int, column c: Int) {
            guard let table, r >= 0, c >= 0, order.indices.contains(r),
                table.tableColumns.indices.contains(c),
                let colIndex = Int(table.tableColumns[c].identifier.rawValue)
            else { return }
            parent.onNavigateForeignKey(order[r], colIndex)
        }

        /// Put the cell at (displayRow, column) into inline-edit mode: seed its text field, make it
        /// editable + first responder. Enter stages the value, Esc cancels.
        func beginEditing(displayRow r: Int, column c: Int) {
            guard let table, parent.editable != nil, r >= 0, c >= 0,
                table.tableColumns.indices.contains(c),
                let cell = table.view(atColumn: c, row: r, makeIfNecessary: true) as? GridCellView
            else { return }
            cell.beginEditing()
        }

        /// Begin inline editing of the frozen cell for a display row — hands off to the pane, which
        /// hosts the editor field over the cell. Same staged-edit flow (stageFrozenEdit) as the grid.
        func beginEditingFrozen(displayRow r: Int) {
            guard parent.editable != nil else { return }
            frozenPane?.beginEditing(displayRow: r)
        }
    }
}

/// Identity of the display order: the sort keys plus the page window. When this changes, a
/// display-row-addressed cell rectangle no longer maps to the same data and is dropped.
struct SelectionStamp: Equatable {
    let sortKeys: [SortKey]
    let start: Int
    let end: Int
}

/// A rectangular cell selection in display space: an anchor cell and an extent cell, each a
/// (display row, table-column view position) pair. Normalized accessors give the inclusive row and
/// column ranges so drawing and copy don't care which corner the drag started from.
struct CellSelection: Equatable {
    var anchorRow: Int
    var anchorCol: Int
    var extentRow: Int
    var extentCol: Int

    var minRow: Int { min(anchorRow, extentRow) }
    var maxRow: Int { max(anchorRow, extentRow) }
    var minCol: Int { min(anchorCol, extentCol) }
    var maxCol: Int { max(anchorCol, extentCol) }

    /// Display rows covered by the rectangle (inclusive), top to bottom.
    var displayRows: [Int] { Array(minRow...maxRow) }
    /// Table-column view positions covered by the rectangle (inclusive), left to right.
    var columnPositions: [Int] { Array(minCol...maxCol) }
    /// Whether this rectangle covers `row` (a display row).
    func covers(row: Int) -> Bool { row >= minRow && row <= maxRow }
}

/// NSTableView subclass: Cmd-C copy, Space -> record mode, rubber-band cell selection, and a copy menu.
final class GridTableView: NSTableView {
    weak var coordinator: SQLDataGrid.Coordinator?
    weak var selectionOverlay: CellSelectionOverlay?
    /// Points the mouse must move before a press counts as a rubber-band drag (Apple's ~2pt).
    private let dragThreshold: CGFloat = 2.0

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            coordinator?.activateRecord()
            return
        }
        super.keyDown(with: event)
    }

    /// ⌘C flows through the responder chain to `copy(_:)`, which also lights up an Edit ▸ Copy menu
    /// item. When a cell rectangle is active it copies that rectangle; otherwise the selected rows.
    @objc func copy(_ sender: Any?) { coordinator?.copySelection(withHeader: false) }

    /// Keep inline cell editing working under the custom mouseDown: the table's text field is a valid
    /// first responder, so double-click/click-to-edit reaches it normally.
    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
        if responder is NSTextField || responder is NSTextView { return true }
        return super.validateProposedFirstResponder(responder, for: event)
    }

    /// Peek-then-delegate: decide click vs. drag before handing off. A double-click, right-click, or a
    /// press on the gutter goes straight to `super` (row selection / doubleAction / editing). A press
    /// on a data cell starts a rubber-band rectangle only once the mouse moves past the threshold;
    /// until then it behaves like a normal single click (placing the row selection + a 1×1 rectangle).
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        let column = self.column(at: point)
        let isDataCell =
            row >= 0 && column >= 0 && tableColumns.indices.contains(column)
            && tableColumns[column].identifier.rawValue != "#"
        let shift = event.modifierFlags.contains(.shift)
        let command = event.modifierFlags.contains(.command)
        // Extend an existing rectangle with shift-click on a data cell.
        let shiftExtendsRect = shift && isDataCell && coordinator?.cellSelection != nil
        // Double-clicks, non-data cells (gutter/empty/header), and ⌘/⇧ row-selection gestures (unless
        // shift is extending a rectangle) keep the built-in behavior — multi-row selection + whole-row
        // copy stay intact.
        guard event.clickCount == 1, isDataCell, !command, (!shift || shiftExtendsRect) else {
            if !shiftExtendsRect { coordinator?.clearCellSelection() }
            super.mouseDown(with: event)
            return
        }

        if shiftExtendsRect {
            coordinator?.extendCellSelection(displayRow: row, columnPosition: column)
        } else {
            coordinator?.beginCellSelection(displayRow: row, columnPosition: column)
        }

        // Run our own tracking loop. If the mouse never crosses the threshold, treat it as a plain
        // click: delegate to super so normal row selection still happens (record mode + editing rely
        // on it). If it drags, we own the loop and extend the rectangle.
        let start = point
        var dragged = false
        trackingLoop: while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            switch next.type {
            case .leftMouseDragged:
                let p = convert(next.locationInWindow, from: nil)
                if !dragged, abs(p.x - start.x) <= dragThreshold, abs(p.y - start.y) <= dragThreshold {
                    continue
                }
                dragged = true
                autoscroll(with: next)
                let clampedRow = clampRow(self.row(at: p), point: p)
                let clampedCol = clampColumn(self.column(at: p))
                coordinator?.extendCellSelection(displayRow: clampedRow, columnPosition: clampedCol)
            case .leftMouseUp:
                break trackingLoop
            default:
                break trackingLoop
            }
        }
        if !dragged, !shiftExtendsRect {
            // A plain click: keep the 1×1 cell rectangle and also perform the normal row selection so
            // record mode / editing see the same row. selectRowIndexes drives the delegate callback.
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }

    /// Clamp a possibly-`-1` row index (drag past a vertical edge) into range. `row(at:)` returns -1
    /// both above the first row and below the last, so use the point's y to pick the near edge.
    private func clampRow(_ value: Int, point: NSPoint) -> Int {
        let last = numberOfRows - 1
        guard last >= 0 else { return 0 }
        if value < 0 { return point.y <= visibleRect.minY ? 0 : last }
        return min(max(value, 0), last)
    }

    /// Clamp a possibly-`-1` column index (drag past a horizontal edge) into the data columns.
    private func clampColumn(_ value: Int) -> Int {
        let last = numberOfColumns - 1
        guard last >= 0 else { return 0 }
        if value < 0 { return last }
        return min(max(value, 0), last)
    }

    /// The cell the last context menu was opened on (row/column in display space), so the menu's
    /// Inspect / Set NULL / Edit items act on the clicked cell.
    private var menuCell: (row: Int, column: Int)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        let column = self.column(at: point)
        menuCell = (row, column)
        if row >= 0, !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        let menu = NSMenu()
        // Inspect is ALWAYS available so the value inspector stays reachable in both read-only and
        // editable modes (double-click is repurposed to edit when the result is editable).
        if row >= 0, column >= 0, tableColumns.indices.contains(column),
            tableColumns[column].identifier.rawValue != "#"
        {
            menu.addItem(withTitle: "Inspect Value…", action: #selector(inspectValue), keyEquivalent: "")
            // Foreign-key jump: offered only when the clicked column references another table and the
            // clicked cell is non-NULL (a NULL FK has nothing to look up).
            if let match = coordinator?.foreignKeyMatch(forColumnPosition: column),
                let value = coordinator?.cellValue(displayRow: row, columnPosition: column),
                !value.isNull
            {
                let item = NSMenuItem(
                    title: "Go to \(match.referencedTable)", action: #selector(navigateForeignKey),
                    keyEquivalent: "")
                menu.addItem(item)
            }
            if coordinator?.parent.editable != nil {
                menu.addItem(withTitle: "Edit Value", action: #selector(editValue), keyEquivalent: "")
                menu.addItem(withTitle: "Set NULL", action: #selector(setNull), keyEquivalent: "")
            }
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "Copy", action: #selector(copyPlain), keyEquivalent: "")
        menu.addItem(withTitle: "Copy with Column Names", action: #selector(copyWithHeader), keyEquivalent: "")
        for item in menu.items { item.target = self }
        return menu
    }

    @objc private func copyPlain() { coordinator?.copySelection(withHeader: false) }
    @objc private func copyWithHeader() { coordinator?.copySelection(withHeader: true) }
    @objc private func inspectValue() {
        guard let c = menuCell else { return }
        coordinator?.inspectClicked(displayRow: c.row, column: c.column)
    }
    @objc private func editValue() {
        guard let c = menuCell else { return }
        coordinator?.beginEditing(displayRow: c.row, column: c.column)
    }
    @objc private func setNull() {
        guard let c = menuCell else { return }
        coordinator?.setNullClicked(displayRow: c.row, column: c.column)
    }
    @objc private func navigateForeignKey() {
        guard let c = menuCell else { return }
        coordinator?.navigateForeignKeyClicked(displayRow: c.row, column: c.column)
    }
}

/// A click-through overlay pinned over the table that draws the rubber-band cell rectangle. It never
/// intercepts mouse events (`hitTest` returns nil), so single-click, double-click, and inline editing
/// all reach the cells beneath it. The rectangle is drawn as a translucent themed fill plus a solid
/// edge so cell text underneath stays legible.
final class CellSelectionOverlay: NSView {
    weak var coordinator: SQLDataGrid.Coordinator?

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let rect = coordinator?.selectionRect() else { return }
        DT.Grid.selectionFill.withAlphaComponent(0.22).setFill()
        rect.fill()
        DT.Grid.selectionFill.withAlphaComponent(0.9).setStroke()
        let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1.5
        border.stroke()
    }
}

/// The left-pinned frozen pane, drawn manually as a single floating view (horizontal axis, so it
/// stays put during horizontal scroll while AppKit scrolls it vertically in lockstep with the rows —
/// the exact, reliable mechanism the original gutter used). It renders the row-number gutter AND the
/// first data column's cells by reading the MAIN table's own row rects for alignment and the shared
/// `SQLGridData.cellStyle` for content (so pills / staged tint / alignment / fonts match the main
/// grid and stay in sync automatically). It draws its own header strip, a right-edge hairline + soft
/// shadow (frozen-layer look), participates in selection/copy/editing, and hosts an inline editor.
final class FrozenColumnView: NSView {
    weak var coordinator: SQLDataGrid.Coordinator?
    /// The inline editor, created lazily and positioned over the cell being edited.
    private var editor: NSTextField?
    private var editingRow: Int?
    /// The clicked display row when a context menu opens, so menu items act on that row.
    private var menuRow: Int?
    /// True while dragging the column divider, so the pane resizes the frozen column live.
    private var resizingColumn = false

    override var isFlipped: Bool { true }

    /// The header height, matched to the main header so the frozen header lines up with it.
    private var headerHeight: CGFloat { coordinator?.table?.headerView?.frame.height ?? 28 }

    override func draw(_ dirtyRect: NSRect) {
        // A floating subview's context is translated by the scroll offset, so the visible region is
        // `visibleRect` (which moves with scrolling), not `bounds`.
        let area = visibleRect
        DT.Grid.base.setFill()
        area.fill()
        guard let coordinator, let table = coordinator.table else { return }
        let gutterW = coordinator.frozenGutterWidth
        let colX = FrozenColumnGeometry.frozenColumnOriginX(gutter: gutterW)
        let colW = coordinator.frozenColumnStoredWidth

        drawHeader(in: area, gutterWidth: gutterW, columnX: colX, columnWidth: colW)

        // Draw one gutter number + one data cell per visible main-table row, aligned to that row's rect.
        let visible = table.rows(in: table.visibleRect)
        guard visible.length > 0 else { drawEdge(area); return }
        let gutterAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: DT.Grid.nullText, .font: DT.monoNSFont(size: 10),
        ]
        for row in visible.location..<(visible.location + visible.length) {
            let rowRect = rowRectInSelf(row, table: table)
            guard rowRect.maxY > area.minY + headerHeight, rowRect.minY < area.maxY else { continue }
            // Selection band, matching the main row's selection.
            if table.selectedRowIndexes.contains(row) {
                DT.Grid.selectionFill.withAlphaComponent(0.35).setFill()
                NSRect(x: area.minX, y: rowRect.minY, width: area.width, height: rowRect.height).fill()
            }
            // Gutter number (right-aligned in the gutter strip).
            let number = coordinator.rowNumber(forDisplayRow: row) as NSNumber
            let numText = number.stringValue as NSString
            let numSize = numText.size(withAttributes: gutterAttrs)
            numText.draw(
                at: NSPoint(x: gutterW - numSize.width - 6, y: rowRect.midY - numSize.height / 2),
                withAttributes: gutterAttrs)
            // Data cell (skip the one being inline-edited — the editor field covers it).
            if editingRow != row {
                drawDataCell(
                    displayRow: row, in: NSRect(x: colX, y: rowRect.minY, width: colW, height: rowRect.height),
                    coordinator: coordinator)
            }
        }
        drawEdge(area)
    }

    /// Draw the frozen header: an empty gutter slot + the frozen column's title, themed like the main
    /// header (which owns the sort arrow for the collapsed main copy of this column).
    private func drawHeader(in area: NSRect, gutterWidth: CGFloat, columnX: CGFloat, columnWidth: CGFloat) {
        let headerRect = NSRect(x: area.minX, y: area.minY, width: area.width, height: headerHeight)
        DT.Grid.headerBackground.setFill()
        headerRect.fill()
        let title = (coordinator?.frozenColumnTitle() ?? "") as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: DT.Grid.headerText, .font: DT.monoNSFont(size: 10, weight: .semibold),
        ]
        let size = title.size(withAttributes: attrs)
        title.draw(
            at: NSPoint(x: columnX + 6, y: headerRect.midY - size.height / 2), withAttributes: attrs)
        DT.Grid.gridline.setStroke()
        let sep = NSBezierPath()
        sep.move(to: NSPoint(x: area.minX, y: headerRect.maxY - 0.5))
        sep.line(to: NSPoint(x: area.maxX, y: headerRect.maxY - 0.5))
        sep.lineWidth = 1
        sep.stroke()
    }

    /// Draw one frozen data cell using the shared `cellStyle` (staged tint, enum pill, alignment,
    /// fonts) — the SAME render instructions the main grid's cells use, so the two never drift.
    private func drawDataCell(displayRow: Int, in rect: NSRect, coordinator: SQLDataGrid.Coordinator) {
        guard let index = coordinator.frozenColumnIndex, coordinator.order.indices.contains(displayRow)
        else { return }
        let original = coordinator.order[displayRow]
        let staged = coordinator.parent.stagedEdits[CellCoord(row: original, column: index)]
        let style = coordinator.parent.data.cellStyle(
            row: original, column: index, stagedValue: staged,
            enumColumns: coordinator.frozenEnumColumns, enumSlots: DT.Grid.enumPalette.count)
        let p = style.presentation
        let font = DT.monoNSFont(size: coordinator.frozenFontSize)
        let inset = rect.insetBy(dx: 6, dy: 0)

        // Pill/tint background (staged amber or enum color), matching GridCellView.configure.
        if style.isStaged {
            drawPill(DT.Grid.stagedTint.withAlphaComponent(0.22), in: inset, textHeight: font.pointSize)
        } else if let slot = style.enumSlot, DT.Grid.enumPalette.indices.contains(slot) {
            drawPill(DT.Grid.enumPalette[slot].withAlphaComponent(0.20), in: inset, textHeight: font.pointSize)
        }

        let text: String
        let color: NSColor
        if style.isStaged {
            text = p.isNull ? "NULL" : p.text
            color = DT.Grid.rowText
        } else if p.isNull {
            text = "NULL"
            color = DT.Grid.nullText
        } else if p.isEmptyText {
            text = "(empty)"
            color = DT.Grid.nullText
        } else if p.role == .bool {
            text = (p.text == "true") ? "✓" : "✗"
            color = DT.Grid.rowText
        } else {
            text = p.text
            color = (p.role == .number) ? DT.Grid.rowText : DT.Grid.rowTextSecondary
        }
        let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: color, .font: font]
        let ns = text as NSString
        let size = ns.size(withAttributes: attrs)
        let trailing = (p.alignment == .trailing) && !style.isStaged && style.enumSlot == nil
        let x = trailing ? inset.maxX - size.width : inset.minX
        ns.draw(at: NSPoint(x: x, y: rect.midY - size.height / 2), withAttributes: attrs)
    }

    private func drawPill(_ color: NSColor, in inset: NSRect, textHeight: CGFloat) {
        let h = min(inset.height - 4, textHeight + 8)
        let pill = NSRect(x: inset.minX - 2, y: inset.midY - h / 2, width: inset.width + 4, height: h)
        color.setFill()
        NSBezierPath(roundedRect: pill, xRadius: 4, yRadius: 4).fill()
    }

    /// The right-edge hairline + soft shadow so the pane reads as a layer above the scrolling data.
    private func drawEdge(_ area: NSRect) {
        DT.Grid.gridline.setStroke()
        let edge = NSBezierPath()
        edge.move(to: NSPoint(x: area.maxX - 0.5, y: area.minY))
        edge.line(to: NSPoint(x: area.maxX - 0.5, y: area.maxY))
        edge.lineWidth = 1
        edge.stroke()
        let shadow = NSGradient(colors: [
            NSColor.black.withAlphaComponent(0.18), NSColor.black.withAlphaComponent(0.0),
        ])
        shadow?.draw(in: NSRect(x: area.maxX, y: area.minY, width: 6, height: area.height), angle: 0)
    }

    /// The display row's rect in this view's (scroll-translated) coordinate space, via window space so
    /// it stays aligned with the main table through scrolling, sort, paging, and density changes.
    private func rowRectInSelf(_ row: Int, table: NSTableView) -> NSRect {
        convert(table.convert(table.rect(ofRow: row), to: nil), from: nil)
    }

    /// The display row under a point in this view (accounting for the header strip), or -1.
    private func displayRow(at point: NSPoint) -> Int {
        guard let table = coordinator?.table, point.y >= visibleRect.minY + headerHeight else { return -1 }
        let inTable = table.convert(NSPoint(x: point.x, y: point.y), from: self)
        return table.row(at: NSPoint(x: table.bounds.midX, y: inTable.y))
    }

    /// Whether a point is over the column-resize hot zone (a few px around the pane's right edge).
    private func onColumnDivider(_ point: NSPoint) -> Bool {
        abs(point.x - visibleRect.maxX) <= 4
    }

    override func resetCursorRects() {
        addCursorRect(NSRect(x: bounds.maxX - 4, y: 0, width: 8, height: bounds.height), cursor: .resizeLeftRight)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if onColumnDivider(point) {
            trackColumnResize(from: point)
            return
        }
        let row = displayRow(at: point)
        guard let coordinator, row >= 0 else { return }
        if event.clickCount == 2 {
            if coordinator.isEditable {
                coordinator.beginEditingFrozen(displayRow: row)
            } else {
                coordinator.inspectFrozen(displayRow: row)
            }
            return
        }
        // Single click: select the whole row (⇧ extends) and anchor a 1×1 cell rectangle on the frozen
        // column so ⌘C copies it as part of the rectangular-copy path.
        coordinator.selectRowFromFrozen(displayRow: row, extending: event.modifierFlags.contains(.shift))
        coordinator.beginCellSelection(displayRow: row, columnPosition: 0)
    }

    /// Drag the pane's right edge to resize the frozen data column, updating the stored width live.
    private func trackColumnResize(from start: NSPoint) {
        guard let coordinator else { return }
        resizingColumn = true
        let gutterW = coordinator.frozenGutterWidth
        trackingLoop: while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let p = convert(next.locationInWindow, from: nil)
            switch next.type {
            case .leftMouseDragged:
                coordinator.frozenColumnStoredWidth = max(48, p.x - gutterW)
                coordinator.layoutFrozenPane()
            case .leftMouseUp:
                break trackingLoop
            default:
                break trackingLoop
            }
        }
        resizingColumn = false
        coordinator.saveFrozenColumnWidth()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = displayRow(at: point)
        menuRow = row
        guard let coordinator, row >= 0 else { return nil }
        coordinator.selectRowFromFrozen(displayRow: row, extending: false)
        let menu = NSMenu()
        menu.addItem(withTitle: "Inspect Value…", action: #selector(inspectValue), keyEquivalent: "")
        if let match = coordinator.frozenForeignKeyMatch(),
            let value = coordinator.frozenCellValue(displayRow: row), !value.isNull
        {
            menu.addItem(
                withTitle: "Go to \(match.referencedTable)", action: #selector(navigateForeignKey),
                keyEquivalent: "")
        }
        if coordinator.isEditable {
            menu.addItem(withTitle: "Edit Value", action: #selector(editValue), keyEquivalent: "")
            menu.addItem(withTitle: "Set NULL", action: #selector(setNull), keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Copy", action: #selector(copyPlain), keyEquivalent: "")
        menu.addItem(withTitle: "Copy with Column Names", action: #selector(copyWithHeader), keyEquivalent: "")
        for item in menu.items { item.target = self }
        return menu
    }

    @objc private func inspectValue() {
        if let r = menuRow { coordinator?.inspectFrozen(displayRow: r) }
    }
    @objc private func navigateForeignKey() {
        if let r = menuRow { coordinator?.navigateForeignKeyFrozen(displayRow: r) }
    }
    @objc private func editValue() {
        if let r = menuRow { coordinator?.beginEditingFrozen(displayRow: r) }
    }
    @objc private func setNull() {
        if let r = menuRow { coordinator?.setNullFrozen(displayRow: r) }
    }
    @objc private func copyPlain() {
        if let r = menuRow { coordinator?.copyFromFrozen(displayRow: r, withHeader: false) }
    }
    @objc private func copyWithHeader() {
        if let r = menuRow { coordinator?.copyFromFrozen(displayRow: r, withHeader: true) }
    }

    // MARK: Inline editing

    /// Open an inline editor over the frozen cell for `displayRow`, seeded with its current value.
    func beginEditing(displayRow row: Int) {
        guard let coordinator, let table = coordinator.table, coordinator.order.indices.contains(row) else {
            return
        }
        endFrozenEditing(commit: true)
        let rowRect = rowRectInSelf(row, table: table)
        let colX = FrozenColumnGeometry.frozenColumnOriginX(gutter: coordinator.frozenGutterWidth)
        let field = NSTextField(
            frame: NSRect(
                x: colX + 2, y: rowRect.minY + 1, width: coordinator.frozenColumnStoredWidth - 4,
                height: rowRect.height - 2))
        field.font = DT.monoNSFont(size: coordinator.frozenFontSize)
        field.textColor = DT.Grid.rowText
        field.backgroundColor = DT.Grid.stagedTint.withAlphaComponent(0.12)
        field.isBordered = false
        field.focusRingType = .none
        field.stringValue = coordinator.frozenEditingText(displayRow: row)
        field.target = self
        field.action = #selector(commitEditor)
        field.delegate = self
        addSubview(field)
        editor = field
        editingRow = row
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
        needsDisplay = true
    }

    @objc private func commitEditor() { endFrozenEditing(commit: true) }

    /// Tear down the inline editor, optionally staging its text first.
    func endFrozenEditing(commit: Bool) {
        guard let field = editor, let row = editingRow else { return }
        let text = field.stringValue
        editor = nil
        editingRow = nil
        field.removeFromSuperview()
        if commit { _ = coordinator?.stageFrozenEdit(displayRow: row, typed: text) }
        needsDisplay = true
    }

    /// ⌘C copies the selected frozen cell / rows through the coordinator's copy path.
    @objc func copy(_ sender: Any?) {
        if let r = menuRow { coordinator?.copyFromFrozen(displayRow: r, withHeader: false) }
    }
}

extension FrozenColumnView: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            endFrozenEditing(commit: true)
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            endFrozenEditing(commit: false)
            return true
        }
        return false
    }
}

/// Row view that themes the selection fill.
final class GridRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        // Reduced alpha so cell text stays legible on saturated colored themes.
        DT.Grid.selectionFill.withAlphaComponent(0.35).setFill()
        dirtyRect.fill()
    }
}

/// A reused cell view: one themed, aligned text field that can flip into inline editing. When the
/// result is editable, double-click (or the context menu) seeds this field with the cell's value and
/// makes it first responder; Enter stages the parsed value, Esc cancels. Staged cells render tinted.
final class GridCellView: NSTableCellView, NSTextFieldDelegate {
    private let label = NSTextField(labelWithString: "")
    /// Set by the coordinator each time the cell is (re)configured, so edit callbacks know where to
    /// stage and whether editing is allowed.
    weak var coordinator: SQLDataGrid.Coordinator?
    var coord: CellCoord?
    var isEditable = false
    private var editing = false
    private var lastFont: NSFont = DT.monoNSFont(size: 12)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.cell?.usesSingleLineMode = true
        label.drawsBackground = false
        label.isBordered = false
        label.isEditable = false
        label.focusRingType = .none
        label.delegate = self
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not implemented") }

    /// The label's current text — used by the headless grid E2E to assert the cell rendered.
    var currentText: String { label.stringValue }

    /// Render this cell from the shared `GridCellStyle`, so the main grid and the frozen first-column
    /// pane style identically. The style carries an enum-palette *slot*; the caller maps it to a
    /// concrete `NSColor` (the palette lives in the app's theme layer) and passes it here.
    func configure(with style: GridCellStyle, font: NSFont, enumColor: NSColor?) {
        configure(with: style.presentation, font: font, enumColor: enumColor, staged: style.isStaged)
    }

    func configure(with p: CellPresentation, font: NSFont, enumColor: NSColor? = nil, staged: Bool = false) {
        // Don't clobber the field while the user is typing in it.
        guard !editing else { return }
        lastFont = font
        label.font = font
        label.wantsLayer = true
        label.isEditable = false
        if staged {
            // Staged (uncommitted) edit → amber tint so it reads as "pending write".
            label.stringValue = p.isNull ? "NULL" : p.text
            label.textColor = DT.Grid.rowText
            label.alignment = (p.alignment == .trailing) ? .right : .left
            label.layer?.backgroundColor = DT.Grid.stagedTint.withAlphaComponent(0.22).cgColor
            label.layer?.cornerRadius = 4
            return
        }
        if let enumColor {
            // Categorical value → a subtle colored pill; the value is non-null text here.
            label.stringValue = p.text
            label.textColor = DT.Grid.rowText
            label.alignment = .left
            label.layer?.backgroundColor = enumColor.withAlphaComponent(0.20).cgColor
            label.layer?.cornerRadius = 4
            return
        }
        label.layer?.backgroundColor = NSColor.clear.cgColor
        label.layer?.cornerRadius = 0
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

    /// Enter inline-edit mode: seed the field with the cell's current (possibly staged) value, make
    /// it editable, and take first responder.
    func beginEditing() {
        guard isEditable, let coord, let coordinator else { return }
        let committed = coordinator.parent.data.value(row: coord.row, column: coord.column)
        let value = coordinator.parent.stagedEdits[coord] ?? committed
        editing = true
        label.isEditable = true
        label.font = lastFont
        label.textColor = DT.Grid.rowText
        label.layer?.backgroundColor = DT.Grid.stagedTint.withAlphaComponent(0.10).cgColor
        label.layer?.cornerRadius = 4
        label.stringValue = SQLCellEditing.editingText(for: value)
        if let window = label.window {
            window.makeFirstResponder(label)
        }
        label.currentEditor()?.selectAll(nil)
    }

    /// Enter commits the typed value into staged state; a value invalid for the column flashes red.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard editing, let coord, let coordinator else { return false }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            let text = label.stringValue
            if coordinator.stageEdit(coord, typed: text) {
                editing = false
                label.isEditable = false
                label.window?.makeFirstResponder(coordinator.table)
            } else {
                flashInvalid()
            }
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            editing = false
            label.isEditable = false
            label.window?.makeFirstResponder(coordinator.table)
            coordinator.reloadPreservingSelection()
            return true
        }
        return false
    }

    /// Losing focus while editing commits the current text (or reverts on parse failure).
    func controlTextDidEndEditing(_ obj: Notification) {
        guard editing, let coord, let coordinator else { return }
        let text = label.stringValue
        editing = false
        label.isEditable = false
        if !coordinator.stageEdit(coord, typed: text) {
            coordinator.reloadPreservingSelection()
        }
    }

    private func flashInvalid() {
        label.layer?.backgroundColor = DT.Grid.invalidTint.withAlphaComponent(0.35).cgColor
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.editing else { return }
            self.label.layer?.backgroundColor = DT.Grid.stagedTint.withAlphaComponent(0.10).cgColor
        }
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
        let descriptors = table.sortDescriptors
        let multi = descriptors.count > 1
        for i in table.tableColumns.indices {
            let rect = headerRect(ofColumn: i)
            guard rect.intersects(dirtyRect) else { continue }
            let col = table.tableColumns[i]
            let title = col.title as NSString
            let size = title.size(withAttributes: attrs)
            let textRect = NSRect(
                x: rect.minX + 6, y: rect.midY - size.height / 2,
                width: max(0, rect.width - 26), height: size.height)
            title.draw(in: textRect, withAttributes: attrs)
            // Draw an arrow (numbered when multiple columns are sorted) for each sorted column.
            if let priority = descriptors.firstIndex(where: { $0.key == col.identifier.rawValue }) {
                let glyph = descriptors[priority].ascending ? "▲" : "▼"
                let badge = (multi ? "\(glyph)\(priority + 1)" : glyph) as NSString
                let bSize = badge.size(withAttributes: attrs)
                badge.draw(
                    at: NSPoint(x: rect.maxX - bSize.width - 6, y: rect.midY - bSize.height / 2),
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
