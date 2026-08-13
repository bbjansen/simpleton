// Sources/Simpleton/Panels/SQL/SQLPanelView.swift
import SimpletonCore
import SwiftUI

/// The SQL client panel: connection picker + query editor + results grid, hosted in the shared
/// client-panel chrome. Schema browser + history are layered on in a later task.
struct SQLPanelView: View {
    @StateObject private var model: SQLPanelModel

    init(appSupportDir: URL) {
        _model = StateObject(wrappedValue: SQLPanelModel(appSupportDir: appSupportDir))
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
            editor
            ThemedDivider()
            SQLResultsGrid(result: model.result)
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
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }

    private var editor: some View {
        VStack(spacing: 4) {
            TextEditor(text: $model.queryText)
                .font(DT.monoFont(size: 12))
                .frame(height: 90)
                .scrollContentBackground(.hidden)
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
            if let err = model.errorMessage, model.isConnected {
                Text(err).font(DT.monoFont(size: 10)).foregroundColor(DT.accentRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }
}
