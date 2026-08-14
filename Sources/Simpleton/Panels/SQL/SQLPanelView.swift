// Sources/Simpleton/Panels/SQL/SQLPanelView.swift
import SimpletonCore
import SimpletonSQL
import SwiftUI

/// The SQL client panel: connection picker + query editor + results grid, hosted in the shared
/// client-panel chrome. Schema browser + history are layered on in a later task.
///
/// The model is injected (owned by `SQLPanelController`), not created here, so the drawer panel and
/// the standalone `SQLWorkspaceView` are two views of one live `SQLPanelModel` — open the workspace
/// and it already reflects the drawer's connection, schema, and last result.
struct SQLPanelView: View {
    @ObservedObject private var model: SQLPanelModel
    @ObservedObject private var themeSettings = ThemeSettings.shared

    init(model: SQLPanelModel) {
        self.model = model
    }

    var body: some View {
        ClientPanelScaffold(
            title: "SQL",
            availability: model.availability,
            autoRefresh: nil,
            onRefresh: { await model.reload() }
        ) {
            content
        }
        .sheet(isPresented: $model.showingEditor) {
            SQLConnectionEditor { connection, secret in
                Task { await model.saveConnection(connection, secret: secret) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .simpletonOpenConnectionGUI)) { _ in
            Task { await model.consumePendingOpen() }  // warm: panel already mounted
        }
        .task {
            await model.consumePendingOpen()  // cold: panel just mounted via reveal
        }
        .themedGlass(DT.surface)  // theme the panel/drawer with the active appearance, like the other panels
    }

    private var content: some View {
        VStack(spacing: 0) {
            connectionBar
            ThemedDivider()
            if !model.tables.isEmpty {
                SQLSchemaBrowser(
                    tables: model.tables,
                    columnsByTable: model.columnsByTable,
                    onExpand: { table in Task { await model.expand(table: table) } },
                    onPickTable: { table in model.pickTable(table) }
                )
                .frame(maxHeight: 160)
                ThemedDivider()
            } else if model.isConnected {
                // Connected, but the database has no tables — say so, so an empty DB doesn't read
                // as "nothing loaded".
                Text("Connected — this database has no tables yet. Run a query to create or query data.")
                    .font(.system(size: 11)).foregroundColor(DT.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                ThemedDivider()
            }
            SQLQueryEditor(model: model, editorHeight: 90)
            ThemedDivider()
            SQLResultsView(
                result: model.result,
                editable: model.editable,
                foreignKeyMatches: model.foreignKeyMatches,
                onCommit: { staged in await SQLEditCommit.commit(staged, model: model) },
                onNavigateForeignKey: { match, value in
                    await model.navigateForeignKey(
                        referencedTable: match.referencedTable,
                        referencedColumn: match.referencedColumn, value: value)
                }
            )
        }
    }

    private var connectionBar: some View {
        HStack(spacing: 6) {
            Picker("", selection: $model.selectedID) {
                Text("Select…").tag(UUID?.none)
                ForEach(model.connections, id: \.id) { c in
                    Text("\(c.name) (\(c.kind.displayName))").tag(UUID?.some(c.id))
                }
            }
            .labelsHidden()
            .onChange(of: model.selectedID) { Task { await model.connectSelected() } }
            Button(model.isConnected ? "Disconnect" : "Connect") {
                Task { model.isConnected ? await model.disconnect() : await model.connect() }
            }
            .disabled(model.selectedID == nil || model.isConnecting)
            Button {
                model.showingEditor = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain).help("New connection")
            Button {
                NotificationCenter.default.post(name: .simpletonExpandSQLWorkspace, object: nil)
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.plain).help("Open full SQL workspace")
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }
}
