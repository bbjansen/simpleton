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

/// The SQL results area: handles empty/status states and hosts the interactive
/// body for a `.rows` result. Read-only. The interactive body is keyed by
/// result identity so its mode/sort/selection reset when a new query arrives.
struct SQLResultsView: View {
    let result: QueryResult?
    @ObservedObject private var themeSettings = ThemeSettings.shared

    var body: some View {
        switch result {
        case .none:
            hint("Run a query to see results.")
        case .status(let affected, let message):
            statusLine(affected: affected, message: message)
        case .rows(let columns, let rows):
            if rows.isEmpty {
                hint("No rows.")
            } else {
                SQLRowsView(columns: columns, rows: rows)
                    .id(resultIdentity(columns: columns, rowCount: rows.count))
            }
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
    @State private var mode: ResultsMode = .grid
    @State private var sortColumn: Int?
    @State private var ascending = true
    @State private var selectedRow: Int?
    @AppStorage("sql.grid.density") private var density: GridDensity = .comfortable

    private var data: SQLGridData { SQLGridData(columns: columns, rows: rows) }

    var body: some View {
        VStack(spacing: 0) {
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
                SQLRecordView(
                    columns: columns,
                    rows: rows,
                    order: data.sortedIndex(sortColumn: sortColumn, ascending: ascending),
                    selectedRow: $selectedRow,
                    onExit: { mode = .grid }
                )
            }
        }
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
}
