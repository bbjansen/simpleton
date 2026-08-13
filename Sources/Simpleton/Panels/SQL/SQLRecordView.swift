// Sources/Simpleton/Panels/SQL/SQLRecordView.swift
import SimpletonSQL
import SwiftUI

/// Record mode: one row's fields as label -> value, filtered by field name,
/// with prev/next stepping that follows the grid's sorted display order.
/// Read-only; reuses SQLCellFormatting. Esc returns to the grid.
struct SQLRecordView: View {
    let columns: [Column]
    let rows: [[SQLValue]]
    /// Original row indices in the grid's current display (sorted) order.
    let order: [Int]
    @Binding var selectedRow: Int?
    let onExit: () -> Void
    @State private var filter = ""
    @FocusState private var focused: Bool

    /// The original row index currently shown (falls back to the first display row).
    private var currentOriginal: Int {
        if let s = selectedRow, rows.indices.contains(s) { return s }
        return order.first ?? 0
    }

    /// Position of the shown row within the display (sorted) order.
    private var displayPosition: Int { order.firstIndex(of: currentOriginal) ?? 0 }

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
        .focusable()
        .focused($focused)
        .onKeyPress(.escape) {
            onExit()
            return .handled
        }
        .onAppear {
            if selectedRow == nil { selectedRow = order.first }
            focused = true
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            TextField("Filter fields…", text: $filter)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 200)
            Spacer()
            Text("row \(order.isEmpty ? 0 : displayPosition + 1) of \(order.count)")
                .font(DT.monoFont(size: 11)).foregroundColor(DT.textTertiary)
            Button {
                step(-1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain).disabled(displayPosition <= 0)
            Button {
                step(1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain).disabled(order.isEmpty || displayPosition >= order.count - 1)
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
        let r = currentOriginal
        guard rows.indices.contains(r), rows[r].indices.contains(col) else { return .null }
        return rows[r][col]
    }

    private func step(_ delta: Int) {
        guard !order.isEmpty else { return }
        let newPos = min(max(displayPosition + delta, 0), order.count - 1)
        selectedRow = order[newPos]
    }
}
