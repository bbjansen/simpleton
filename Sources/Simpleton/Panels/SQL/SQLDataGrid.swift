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
    /// Staged (uncommitted) edits keyed by original-row/column. The grid renders these tinted and
    /// prefers them over the underlying value.
    @Binding var stagedEdits: [CellCoord: SQLValue]
    var onActivateRecord: () -> Void
    /// "Inspect Value…" — always available (right-click), and the double-click action when read-only.
    var onInspect: (Int, Int) -> Void

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

        context.coordinator.table = table
        context.coordinator.observeColumnLayout()
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
        /// Original row indices shown on the current page, in display (sorted) order. This is the
        /// per-page slice of the full sorted order; all row math for the visible table uses this.
        private(set) var order: [Int] = []
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
            for obs in [resizeObserver, moveObserver].compactMap({ $0 }) {
                NotificationCenter.default.removeObserver(obs)
            }
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
            ) { [weak self] _ in self?.saveColumnOrder() }
        }

        private func widthsKey() -> String { "sql.grid.widths.\(parent.data.columnSignature)" }
        private func orderKey() -> String { "sql.grid.order.\(parent.data.columnSignature)" }

        func saveColumnWidths() {
            guard !isRestoringLayout, let table else { return }
            var widths: [String: Double] = [:]
            for col in table.tableColumns where col.identifier.rawValue != "#" {
                widths[col.identifier.rawValue] = Double(col.width)
            }
            UserDefaults.standard.set(widths, forKey: widthsKey())
        }

        func restoreColumnWidths() {
            guard let table,
                let saved = UserDefaults.standard.dictionary(forKey: widthsKey()) as? [String: Double]
            else { return }
            isRestoringLayout = true
            defer { isRestoringLayout = false }
            for col in table.tableColumns where col.identifier.rawValue != "#" {
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
            // Move each saved identifier into its position; the gutter ("#") stays at index 0.
            for (target, id) in saved.enumerated() {
                let to = 1 + target
                guard to < table.tableColumns.count,
                    let from = table.tableColumns.firstIndex(where: { $0.identifier.rawValue == id }),
                    from != to
                else { continue }
                table.moveColumn(from, toColumn: to)
            }
        }

        /// Rebuild when the column identity changes — not merely the count, or a
        /// new query with the same column count keeps the previous headers.
        func needsColumnRebuild() -> Bool { builtColumns != parent.data.columns }

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
            builtColumns = parent.data.columns
            enumCols = parent.data.enumColumns()
            restoreColumnWidths()
            restoreColumnOrder()
        }

        func applyOrder() {
            let full = parent.data.sortedIndex(by: parent.sortKeys)
            // Slice the sorted order to the current page window. Bounds are already clamped by
            // SQLPaging, but guard against a stale binding pass that hasn't re-derived the page yet.
            let start = min(max(parent.page.start, 0), full.count)
            let end = min(max(parent.page.end, start), full.count)
            order = Array(full[start..<end])
        }

        func applyTheme() {
            guard let table else { return }
            table.gridColor = DT.Grid.gridline
            table.headerView?.needsDisplay = true
        }

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
                // Gutter shows the absolute (paged) row number so identity stays readable across pages.
                cell.configureGutter(number: parent.page.start + row + 1)
                return cell
            }
            guard let colIndex = Int(id) else { return cell }
            let original = order.indices.contains(row) ? order[row] : row
            let coord = CellCoord(row: original, column: colIndex)
            // A staged edit overrides the underlying value and is shown tinted.
            let staged = parent.stagedEdits[coord]
            let value = staged ?? parent.data.value(row: original, column: colIndex)
            cell.coordinator = self
            cell.coord = coord
            cell.isEditable = parent.editable != nil
            var enumColor: NSColor?
            if staged == nil, enumCols.contains(colIndex), case .text(let s) = value, !s.isEmpty {
                let palette = DT.Grid.enumPalette
                if !palette.isEmpty { enumColor = palette[parent.data.enumColorIndex(s, slots: palette.count)] }
            }
            cell.configure(
                with: SQLCellFormatting.present(value), font: DT.monoNSFont(size: fontSize),
                enumColor: enumColor, staged: staged != nil)
            return cell
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
            // updateNSView, which re-orders and reloads.
            isApplyingSort = true
            tableView.sortDescriptors = keys.map { NSSortDescriptor(key: String($0.column), ascending: $0.ascending) }
            isApplyingSort = false
            parent.sortKeys = keys
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

        /// Double-click a data cell → edit it (when the result is editable) or inspect its full value
        /// (when read-only). Ignores the gutter and header.
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

        /// Put the cell at (displayRow, column) into inline-edit mode: seed its text field, make it
        /// editable + first responder. Enter stages the value, Esc cancels.
        func beginEditing(displayRow r: Int, column c: Int) {
            guard let table, parent.editable != nil, r >= 0, c >= 0,
                table.tableColumns.indices.contains(c),
                let cell = table.view(atColumn: c, row: r, makeIfNecessary: true) as? GridCellView
            else { return }
            cell.beginEditing()
        }
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
