// Sources/Simpleton/Panels/SQL/SQLSchemaBrowser.swift
import AppKit
import SimpletonSQL
import SwiftUI

/// A searchable schema tree: tables/views → columns, with per-column detail (type, primary-key
/// badge, nullability) and copy/insert context actions. Double-clicking a table inserts a starter
/// SELECT; the filter narrows the visible tables by name.
struct SQLSchemaBrowser: View {
    let tables: [TableInfo]
    let columnsByTable: [String: [ColumnInfo]]
    let onExpand: (String) -> Void
    let onPickTable: (String) -> Void

    @State private var expanded: Set<String> = []
    @State private var search = ""

    private var filteredTables: [TableInfo] {
        guard !search.isEmpty else { return tables }
        let needle = search.lowercased()
        return tables.filter { $0.name.lowercased().contains(needle) }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider().overlay(DT.border)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredTables, id: \.name) { table in
                        tableRow(table)
                        if expanded.contains(table.name) {
                            ForEach(columnsByTable[table.name] ?? [], id: \.name) { col in
                                columnRow(col)
                            }
                        }
                    }
                    if filteredTables.isEmpty {
                        Text(tables.isEmpty ? "No tables." : "No tables match “\(search)”.")
                            .font(DT.monoFont(size: 10)).foregroundColor(DT.textFaint)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
            }
            .scrollContentBackground(.hidden)
        }
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").font(.system(size: 9)).foregroundColor(DT.textFaint)
            TextField("Filter tables…", text: $search)
                .textFieldStyle(.plain).font(DT.monoFont(size: 10)).foregroundColor(DT.textSecondary)
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 9))
                }
                .buttonStyle(.plain).foregroundColor(DT.textFaint).help("Clear filter")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
    }

    private func tableRow(_ table: TableInfo) -> some View {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded { onPickTable(table.name) })
        .contextMenu {
            Button("Insert SELECT") { onPickTable(table.name) }
            Button("Copy Name") { copy(table.name) }
        }
    }

    private func columnRow(_ col: ColumnInfo) -> some View {
        HStack(spacing: 4) {
            if col.isPrimaryKey {
                Image(systemName: "key.fill").font(.system(size: 8))
                    .foregroundColor(DT.accentAmber).help("Primary key")
            }
            Text(col.name).font(DT.monoFont(size: 10)).foregroundColor(DT.textTertiary)
            Text(col.type).font(DT.monoFont(size: 9)).foregroundColor(DT.textFaint)
            if !col.nullable {
                Text("NOT NULL").font(.system(size: 7, weight: .medium)).foregroundColor(DT.textFaint)
                    .padding(.horizontal, 3).padding(.vertical, 1)
                    .background(DT.hover).cornerRadius(3)
            }
            Spacer()
        }
        .padding(.leading, col.isPrimaryKey ? 14 : 22)
        .contextMenu { Button("Copy Name") { copy(col.name) } }
    }

    private func toggle(_ table: String) {
        if expanded.contains(table) {
            expanded.remove(table)
        } else {
            expanded.insert(table)
            onExpand(table)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
