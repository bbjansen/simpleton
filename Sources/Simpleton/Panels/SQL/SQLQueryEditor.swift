// Sources/Simpleton/Panels/SQL/SQLQueryEditor.swift
import AppKit
import SimpletonCore
import SimpletonSQL
import SwiftUI

/// The shared query editor: a `TextEditor` bound to `model.queryText`, a "modifies data" warning, a
/// history menu, a Run button (⌘↵), and the inline error line. Extracted from `SQLPanelView` so the
/// drawer panel and the standalone `SQLWorkspaceView` render the *same* editor against one shared
/// `SQLPanelModel`. Sub-project 2 replaces the bare `TextEditor` with a real `SQLCodeEditor` here.
struct SQLQueryEditor: View {
    @ObservedObject var model: SQLPanelModel
    @ObservedObject private var themeSettings = ThemeSettings.shared
    /// Fixed editor height for the drawer's cramped layout; `nil` lets it fill (the workspace split).
    let editorHeight: CGFloat?

    init(model: SQLPanelModel, editorHeight: CGFloat? = nil) {
        self.model = model
        self.editorHeight = editorHeight
    }

    var body: some View {
        VStack(spacing: 4) {
            editorField
            controls
            if let err = model.errorMessage, model.isConnected {
                Text(err).font(DT.monoFont(size: 10)).foregroundColor(DT.accentRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }

    @ViewBuilder
    private var editorField: some View {
        let field = SQLCodeEditor(
            text: $model.queryText,
            tableNames: model.tables.map(\.name),
            columnNames: Array(Set(model.columnsByTable.values.flatMap { $0.map(\.name) })).sorted(),
            font: DT.monoNSFont(size: 12),
            onRun: { Task { await model.runQuery() } },
            onRunSelection: { sql in Task { await model.runSelection(sql) } }
        )
        if let editorHeight {
            field.frame(height: editorHeight)
        } else {
            field.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var controls: some View {
        HStack {
            if model.queryModifiesData && !model.queryText.isEmpty {
                Label("modifies data", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10)).foregroundColor(DT.accentRed)
            }
            Spacer()
            if let summary = model.lastRunSummary {
                Text(summary).font(DT.monoFont(size: 10)).foregroundColor(DT.textTertiary)
                    .help("Rows returned and query time")
            }
            savedQueriesMenu
            if !model.historyItems.isEmpty {
                Menu {
                    ForEach(model.historyItems, id: \.self) { item in
                        Button(item) { model.queryText = item }
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .menuStyle(.borderlessButton).fixedSize().help("Query history")
            }
            Button("Run  ⌘↵") { Task { await model.runQuery() } }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.isConnected)
        }
    }

    /// The bookmark menu: apply a saved query (click its name), save the current editor text under a
    /// name, or delete a saved query. Disabled until connected (saves are per-database).
    private var savedQueriesMenu: some View {
        Menu {
            if model.savedQueries.isEmpty {
                Text("No saved queries")
            } else {
                ForEach(model.savedQueries, id: \.name) { q in
                    Button(q.name) { model.queryText = q.sql }
                }
                Divider()
                Menu("Delete") {
                    ForEach(model.savedQueries, id: \.name) { q in
                        Button(q.name) { Task { await model.removeSavedQuery(name: q.name) } }
                    }
                }
            }
            Divider()
            Button("Save current query…") { promptAndSaveQuery() }
                .disabled(model.queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } label: {
            Image(systemName: "bookmark")
        }
        .menuStyle(.borderlessButton).fixedSize().help("Saved queries")
        .disabled(!model.isConnected)
    }

    /// Prompt for a name (an `NSAlert` with a text field) and save the current editor text under it.
    /// Runs modally on the main thread; a blank name cancels the save.
    private func promptAndSaveQuery() {
        let alert = NSAlert()
        alert.messageText = "Save Query"
        alert.informativeText = "Name this query to reuse it on this connection."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Query name"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task { await model.saveCurrentQuery(name: name) }
    }
}

/// Turns the results grid's staged cell edits into `RowEdit`s and commits them through the model.
/// Shared by the drawer panel and the workspace so both wire `SQLResultsView.onCommit` identically.
enum SQLEditCommit {
    /// Group staged edits by row, resolve each row's primary-key values from the live result grid,
    /// and hand the model one `RowEdit` per row (it builds a parameterized UPDATE for each). Values
    /// are read from the result, never formatted into SQL.
    @MainActor
    static func commit(_ staged: [CellCoord: SQLValue], model: SQLPanelModel) async {
        guard let editable = model.editable, case .rows(let columns, let rows) = model.result else { return }
        let columnIndex = Dictionary(uniqueKeysWithValues: columns.enumerated().map { ($0.element.name, $0.offset) })

        var changesByRow: [Int: [(column: String, value: SQLValue)]] = [:]
        for (coord, value) in staged {
            guard columns.indices.contains(coord.column) else { continue }
            changesByRow[coord.row, default: []].append((column: columns[coord.column].name, value: value))
        }

        var edits: [RowEdit] = []
        for (rowIndex, changes) in changesByRow {
            guard rows.indices.contains(rowIndex) else { continue }
            var key: [(column: String, value: SQLValue)] = []
            var complete = true
            for pk in editable.primaryKey {
                guard let ci = columnIndex[pk], rows[rowIndex].indices.contains(ci) else {
                    complete = false
                    break
                }
                key.append((column: pk, value: rows[rowIndex][ci]))
            }
            guard complete, !changes.isEmpty else { continue }
            edits.append(RowEdit(key: key, changes: changes))
        }
        await model.commitEdits(edits)
    }
}
