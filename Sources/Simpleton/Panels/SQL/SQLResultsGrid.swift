// Sources/Simpleton/Panels/SQL/SQLResultsGrid.swift
import SimpletonSQL
import SwiftUI

/// A generic (unknown-columns) results grid for a `QueryResult`.
struct SQLResultsGrid: View {
    let result: QueryResult?

    var body: some View {
        switch result {
        case .none:
            emptyHint("Run a query to see results.")
        case .status(let affected, let message):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle").foregroundColor(DT.accentGreen)
                Text("\(affected) row\(affected == 1 ? "" : "s") affected — \(message)")
                    .font(DT.monoFont(size: 11)).foregroundColor(DT.textSecondary)
                Spacer()
            }
            .padding(8)
        case .rows(let columns, let rows):
            if rows.isEmpty {
                emptyHint("No rows.")
            } else {
                grid(columns: columns, rows: rows)
            }
        }
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundColor(DT.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func grid(columns: [Column], rows: [[SQLValue]]) -> some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(columns.indices, id: \.self) { i in
                        cell(columns[i].name, header: true)
                    }
                }
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(rows[r].indices, id: \.self) { c in
                            cell(rows[r][c].displayString, header: false, isNull: rows[r][c] == .null)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func cell(_ text: String, header: Bool, isNull: Bool = false) -> some View {
        Text(text)
            .font(DT.monoFont(size: 11))
            .fontWeight(header ? .semibold : .regular)
            .foregroundColor(header ? DT.textPrimary : (isNull ? DT.textFaint : DT.textSecondary))
            .lineLimit(1)
            .frame(width: 160, alignment: .leading)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .overlay(Rectangle().fill(.black.opacity(0.08)).frame(height: 1), alignment: .bottom)
    }
}
