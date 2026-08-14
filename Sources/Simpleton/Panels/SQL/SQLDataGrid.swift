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
    /// Double-click a data cell → inspect (originalRow, columnIndex).
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
        private(set) var order: [Int] = []
        private var builtColumns: [Column] = []
        private var isProgrammaticReload = false
        private let cellID = NSUserInterfaceItemIdentifier("gridCell")
        private let rowID = NSUserInterfaceItemIdentifier("gridRow")

        init(_ parent: SQLDataGrid) { self.parent = parent }

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
        }

        func applyOrder() {
            order = parent.data.sortedIndex(sortColumn: parent.sortColumn, ascending: parent.ascending)
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
                cell.configureGutter(number: row + 1)
                return cell
            }
            guard let colIndex = Int(id) else { return cell }
            let original = order.indices.contains(row) ? order[row] : row
            cell.configure(
                with: SQLCellFormatting.present(parent.data.value(row: original, column: colIndex)),
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
            guard !isProgrammaticReload, let table else { return }
            let r = table.selectedRow
            let newValue = (r >= 0 && order.indices.contains(r)) ? order[r] : nil
            if parent.selectedRow != newValue { parent.selectedRow = newValue }
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            // Mutate the bindings only; the resulting SwiftUI update re-runs
            // updateNSView, which applies the new order and reloads once.
            if let sd = tableView.sortDescriptors.first, let key = sd.key, let col = Int(key) {
                parent.sortColumn = col
                parent.ascending = sd.ascending
            } else {
                parent.sortColumn = nil
            }
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

        /// Double-click on a data cell → inspect its full value. Ignores the gutter and header.
        @objc func cellDoubleClicked(_ sender: NSTableView) {
            let r = sender.clickedRow
            let c = sender.clickedColumn
            guard r >= 0, c >= 0, sender.tableColumns.indices.contains(c),
                let colIndex = Int(sender.tableColumns[c].identifier.rawValue)
            else { return }
            let original = order.indices.contains(r) ? order[r] : r
            parent.onInspect(original, colIndex)
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
        // Reduced alpha so cell text stays legible on saturated colored themes.
        DT.Grid.selectionFill.withAlphaComponent(0.35).setFill()
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
            let textRect = NSRect(
                x: rect.minX + 6, y: rect.midY - size.height / 2,
                width: max(0, rect.width - 24), height: size.height)
            title.draw(in: textRect, withAttributes: attrs)
            if let sd = sort, sd.key == col.identifier.rawValue {
                let arrow = (sd.ascending ? "▲" : "▼") as NSString
                let aSize = arrow.size(withAttributes: attrs)
                arrow.draw(
                    at: NSPoint(x: rect.maxX - aSize.width - 6, y: rect.midY - aSize.height / 2),
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
