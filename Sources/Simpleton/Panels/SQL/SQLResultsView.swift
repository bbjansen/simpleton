// Sources/Simpleton/Panels/SQL/SQLResultsView.swift
import AppKit
import SimpletonSQL
import SwiftUI
import UniformTypeIdentifiers

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

/// Display page size for the results grid. `.all` shows every row on one page; the numeric cases cap
/// the page window. Persisted as its `rawValue` via `@AppStorage`.
enum GridPageSize: Int, CaseIterable, Identifiable {
    case p500 = 500, p1000 = 1000, p5000 = 5000, all = 0
    var id: Int { rawValue }
    /// The page size passed to `SQLPaging` (`nil` = All rows on one page).
    var size: Int? { self == .all ? nil : rawValue }
    var label: String { self == .all ? "All" : String(rawValue) }
}

/// The SQL results area: handles empty/status states and hosts the interactive body for a `.rows`
/// result. Editable when `editable` is non-nil (double-click a cell to edit, staged with a commit
/// bar); read-only otherwise. The interactive body is keyed by result identity so its
/// mode/sort/selection/staged-edits reset when a new query arrives.
struct SQLResultsView: View {
    let result: QueryResult?
    /// Non-nil when the current result is a single-table SELECT we can UPDATE — enables editing.
    let editable: EditableTarget?
    /// FK jumps for the current result, keyed by result-column index. Drives the grid's right-click
    /// "Go to <referencedTable>" on an FK cell.
    let foreignKeyMatches: [Int: SQLForeignKeyMatcher.Match]
    /// Commit staged edits: called with the grid's staged edits; returns after the model has written
    /// them and re-queried (so the view can clear its staged state).
    let onCommit: ([CellCoord: SQLValue]) async -> Void
    /// Navigate a foreign key: run `SELECT * FROM ref WHERE refcol = ?` with the clicked cell's value
    /// bound (never interpolated) and show the referenced row.
    let onNavigateForeignKey: (SQLForeignKeyMatcher.Match, SQLValue) async -> Void
    /// One entry per statement from the last run; a tab strip appears when there is more than one.
    let statementResults: [StatementResult]
    /// Which statement's result is shown (drives `result`, kept in sync by the model).
    let selectedResultIndex: Int
    /// Switch to another statement's result tab.
    let onSelectResult: (Int) -> Void
    @ObservedObject private var themeSettings = ThemeSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            if statementResults.count > 1 {
                resultTabBar
                ThemedDivider()
            }
            resultContent
        }
    }

    @ViewBuilder private var resultContent: some View {
        switch result {
        case .none:
            hint("Run a query to see results.")
        case .status(let affected, let message):
            statusLine(affected: affected, message: message)
        case .rows(let columns, let rows):
            if rows.isEmpty {
                hint("No rows.")
            } else {
                SQLRowsView(
                    columns: columns, rows: rows, editable: editable,
                    foreignKeyMatches: foreignKeyMatches, onCommit: onCommit,
                    onNavigateForeignKey: onNavigateForeignKey
                )
                .id(resultIdentity(columns: columns, rowCount: rows.count))
            }
        }
    }

    /// A horizontal strip of statement tabs, one per result, showing the statement's leading keyword
    /// and row/affected count. The active tab is highlighted; clicking one shows that result.
    private var resultTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(statementResults.enumerated()), id: \.offset) { index, sr in
                    Button {
                        onSelectResult(index)
                    } label: {
                        Text(Self.tabLabel(sr, index))
                            .font(DT.monoFont(size: 10))
                            .foregroundColor(index == selectedResultIndex ? DT.textPrimary : DT.textTertiary)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(index == selectedResultIndex ? DT.hover : Color.clear)
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
        }
    }

    /// A compact tab label: 1-based position, the statement's leading keyword, and its row/affected
    /// count — e.g. `1. SELECT (12)`.
    private static func tabLabel(_ sr: StatementResult, _ index: Int) -> String {
        let verb = sr.sql.split(whereSeparator: { $0.isWhitespace }).first.map { String($0).uppercased() } ?? "SQL"
        switch sr.result {
        case .rows(_, let rows): return "\(index + 1). \(verb) (\(rows.count))"
        case .status(let affected, _): return "\(index + 1). \(verb) (\(affected))"
        }
    }

    /// A per-result identity so SwiftUI recreates `SQLRowsView` (resetting its
    /// mode/sort/selection state) when the query changes shape.
    private func resultIdentity(columns: [Column], rowCount: Int) -> String {
        columns.map(\.name).joined(separator: "\u{1}") + "\u{2}\(rowCount)"
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

/// The interactive body for a non-empty row result: Grid|Record toggle, density
/// control, and shared selection. Recreated per result via `.id(...)` so its
/// `@State` (mode/sort/selection) resets when a new query arrives.
private struct SQLRowsView: View {
    let columns: [Column]
    let rows: [[SQLValue]]
    let editable: EditableTarget?
    let foreignKeyMatches: [Int: SQLForeignKeyMatcher.Match]
    let onCommit: ([CellCoord: SQLValue]) async -> Void
    let onNavigateForeignKey: (SQLForeignKeyMatcher.Match, SQLValue) async -> Void
    @State private var mode: ResultsMode = .grid
    @State private var sortKeys: [SortKey] = []
    @State private var selectedRow: Int?
    @State private var inspected: InspectedCell?
    @State private var stagedEdits: [CellCoord: SQLValue] = [:]
    @State private var isCommitting = false
    /// Current display page (0-based) over the sorted order. Reset to 0 when the result changes (the
    /// view is recreated via `.id(...)`) or when the page size changes; preserved across re-sorting.
    @State private var page = 0
    @AppStorage("sql.grid.density") private var density: GridDensity = .comfortable
    @AppStorage("sql.grid.pageSize") private var pageSizeRaw = GridPageSize.p1000.rawValue

    private var pageSize: GridPageSize { GridPageSize(rawValue: pageSizeRaw) ?? .p1000 }

    private var data: SQLGridData { SQLGridData(columns: columns, rows: rows) }

    /// Clamped bounds of the current page over the full row count (independent of sort, which only
    /// reorders within the same total).
    private var pageBounds: PageBounds {
        SQLPaging.bounds(total: rows.count, pageSize: pageSize.size, page: page)
    }

    /// Original row indices on the current page, in display (sorted) order — the same slice the grid
    /// shows, so record-mode stepping stays within the page and matches the grid.
    private var pagedOrder: [Int] {
        let full = data.sortedIndex(by: sortKeys)
        let b = pageBounds
        let start = min(max(b.start, 0), full.count)
        let end = min(max(b.end, start), full.count)
        return Array(full[start..<end])
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar(rowCount: rows.count)
            ThemedDivider()
            if mode == .grid {
                SQLDataGrid(
                    data: data,
                    sortKeys: $sortKeys,
                    selectedRow: $selectedRow,
                    page: pageBounds,
                    rowHeight: density.rowHeight,
                    editable: editable,
                    foreignKeyMatches: foreignKeyMatches,
                    stagedEdits: $stagedEdits,
                    onActivateRecord: { mode = .record },
                    onInspect: { original, col in
                        inspected = InspectedCell(
                            column: columns.indices.contains(col) ? columns[col].name : "",
                            value: data.value(row: original, column: col))
                    },
                    onNavigateForeignKey: { original, col in
                        guard let match = foreignKeyMatches[col] else { return }
                        let value = data.value(row: original, column: col)
                        Task { await onNavigateForeignKey(match, value) }
                    }
                )
            } else {
                SQLRecordView(
                    columns: columns,
                    rows: rows,
                    order: pagedOrder,
                    selectedRow: $selectedRow,
                    onExit: { mode = .grid }
                )
            }
            if editable != nil, !stagedEdits.isEmpty {
                ThemedDivider()
                commitBar
            }
        }
        .sheet(item: $inspected) { CellDetailSheet(cell: $0) }
    }

    /// The commit bar: appears below the grid whenever there are staged edits. Discard clears them
    /// (reverting the grid to committed values); Commit writes them via the model and re-queries.
    private var commitBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.and.pencil").font(.system(size: 11)).foregroundColor(DT.accentAmber)
            Text("\(stagedEdits.count) pending change\(stagedEdits.count == 1 ? "" : "s")")
                .font(DT.monoFont(size: 11)).foregroundColor(DT.textSecondary)
            Spacer()
            Button("Discard") { stagedEdits = [:] }
                .disabled(isCommitting)
            Button("Commit") {
                let edits = stagedEdits
                isCommitting = true
                Task {
                    await onCommit(edits)
                    // The model re-queries on success; this view is recreated by `.id(...)` when the
                    // fresh result arrives, so clearing here also covers the no-change edge.
                    stagedEdits = [:]
                    isCommitting = false
                }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(isCommitting)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(DT.accentAmber.opacity(0.08))
    }

    private func toolbar(rowCount: Int) -> some View {
        HStack(spacing: 8) {
            Picker("", selection: $mode) {
                ForEach(ResultsMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Spacer()
            pagination(rowCount: rowCount)
            Menu {
                ForEach(GridDensity.allCases, id: \.self) { d in
                    Button(d.label) { density = d }
                }
            } label: {
                Image(systemName: "arrow.up.and.down.text.horizontal")
            }
            .menuStyle(.borderlessButton).fixedSize().help("Row density")
            exportMenu
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
    }

    /// Export / copy the full result set (all rows, in query order — independent of the display page).
    private var exportMenu: some View {
        Menu {
            Button("Copy as CSV") { copyToPasteboard(SQLResultExporter.csv(columns: columns, rows: rows)) }
            Button("Copy as JSON") { copyToPasteboard(SQLResultExporter.json(columns: columns, rows: rows)) }
            Divider()
            Button("Save as CSV…") {
                saveToFile("csv", .commaSeparatedText, SQLResultExporter.csv(columns: columns, rows: rows))
            }
            Button("Save as JSON…") { saveToFile("json", .json, SQLResultExporter.json(columns: columns, rows: rows)) }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .menuStyle(.borderlessButton).fixedSize().help("Export results")
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func saveToFile(_ ext: String, _ type: UTType, _ content: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "results.\(ext)"
        panel.allowedContentTypes = [type]
        panel.isExtensionHidden = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Page-size picker + prev/next + "Rows X–Y of N". Changing the page size resets to page 0 (so the
    /// user isn't stranded past the new last page); prev/next are disabled at the ends.
    @ViewBuilder private func pagination(rowCount: Int) -> some View {
        let bounds = pageBounds
        let pageCount = SQLPaging.pageCount(total: rowCount, pageSize: pageSize.size)
        Picker("", selection: pageSizeBinding) {
            ForEach(GridPageSize.allCases) { Text($0.label).tag($0) }
        }
        .labelsHidden().fixedSize().help("Rows per page")
        if pageCount > 1 {
            Button {
                page = max(0, bounds.page - 1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain).disabled(bounds.page <= 0).help("Previous page")
            Button {
                page = min(pageCount - 1, bounds.page + 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain).disabled(bounds.page >= pageCount - 1).help("Next page")
        }
        Text("Rows \(bounds.firstRowNumber)–\(bounds.lastRowNumber) of \(rowCount)")
            .font(DT.monoFont(size: 11)).foregroundColor(DT.textTertiary)
    }

    /// Writes the persisted page size and resets to page 0 on change, so switching to a coarser size
    /// never leaves `page` past the new last page.
    private var pageSizeBinding: Binding<GridPageSize> {
        Binding(
            get: { pageSize },
            set: { newValue in
                pageSizeRaw = newValue.rawValue
                page = 0
            })
    }
}
