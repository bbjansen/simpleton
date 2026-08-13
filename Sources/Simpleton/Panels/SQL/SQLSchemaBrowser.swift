// Sources/Simpleton/Panels/SQL/SQLSchemaBrowser.swift
import SimpletonSQL
import SwiftUI

/// A lazy schema tree: tables/views → columns. Clicking a table inserts a starter SELECT.
struct SQLSchemaBrowser: View {
    let tables: [TableInfo]
    let columnsByTable: [String: [ColumnInfo]]
    let onExpand: (String) -> Void
    let onPickTable: (String) -> Void

    @State private var expanded: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(tables, id: \.name) { table in
                    Button {
                        toggle(table.name)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: expanded.contains(table.name) ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8)).foregroundColor(DT.textTertiary)
                            Image(systemName: table.kind == .view ? "eye" : "tablecells")
                                .font(.system(size: 10)).foregroundColor(DT.textTertiary)
                            Text(table.name).font(DT.monoFont(size: 11)).foregroundColor(DT.textSecondary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture(count: 2).onEnded { onPickTable(table.name) })
                    if expanded.contains(table.name) {
                        ForEach(columnsByTable[table.name] ?? [], id: \.name) { col in
                            HStack(spacing: 4) {
                                Text(col.name).font(DT.monoFont(size: 10)).foregroundColor(DT.textTertiary)
                                Text(col.type).font(DT.monoFont(size: 9)).foregroundColor(DT.textFaint)
                                Spacer()
                            }
                            .padding(.leading, 22)
                        }
                    }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
        }
        .scrollContentBackground(.hidden)
    }

    private func toggle(_ table: String) {
        if expanded.contains(table) {
            expanded.remove(table)
        } else {
            expanded.insert(table)
            onExpand(table)
        }
    }
}
