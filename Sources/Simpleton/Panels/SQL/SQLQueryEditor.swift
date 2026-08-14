// Sources/Simpleton/Panels/SQL/SQLQueryEditor.swift
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
        let field = TextEditor(text: $model.queryText)
            .font(DT.monoFont(size: 12))
            .scrollContentBackground(.hidden)
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
