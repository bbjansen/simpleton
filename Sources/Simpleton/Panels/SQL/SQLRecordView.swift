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
            Button {
                step(-1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain).disabled(rowIndex <= 0)
            Button {
                step(1)
            } label: {
                Image(systemName: "chevron.down")
            }
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
