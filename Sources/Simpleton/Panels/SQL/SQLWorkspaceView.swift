// Sources/Simpleton/Panels/SQL/SQLWorkspaceView.swift
import SimpletonCore
import SimpletonSQL
import SwiftUI

/// The dedicated full SQL workspace: a 3-zone layout (collapsible schema sidebar │ query editor over
/// results) reusing today's `SQLSchemaBrowser`, the shared `SQLQueryEditor`, and `SQLResultsView`.
/// It binds to an *injected* `SQLPanelModel` (owned by `SQLPanelController`), so it renders the live
/// connection / schema / last result immediately — it is a second view of the drawer's session, not
/// a new one. Hosted in a standalone `NSWindow` from `AppDelegate` when the drawer's Expand fires.
///
/// This is the foundation (sub-project 1): it drops in today's components as-is. Later sub-projects
/// upgrade the editor (real code editor + tabs), the schema browser (searchable tree), and the
/// results actions (per-statement tabs + export).
struct SQLWorkspaceView: View {
    @ObservedObject private var model: SQLPanelModel
    @ObservedObject private var themeSettings = ThemeSettings.shared
    @StateObject private var layout = SQLWorkspaceLayout()

    init(model: SQLPanelModel) {
        self.model = model
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            ThemedDivider()
            GeometryReader { geo in
                HStack(spacing: 0) {
                    if !layout.sidebarCollapsed {
                        sidebar
                            .frame(width: layout.sidebarWidth)
                        sidebarResizeHandle
                    }
                    center(totalHeight: geo.size.height)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(DT.base)
        .sheet(isPresented: $model.showingEditor) {
            SQLConnectionEditor { connection, secret in
                Task { await model.saveConnection(connection, secret: secret) }
            }
        }
        .themedGlass(DT.surface)
    }

    // MARK: - Toolbar (connection ● status · picker · Run)

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                layout.sidebarCollapsed.toggle()
            } label: {
                Image(systemName: "sidebar.left")
                    .foregroundColor(layout.sidebarCollapsed ? DT.textTertiary : DT.textSecondary)
            }
            .buttonStyle(.plain).help(layout.sidebarCollapsed ? "Show schema" : "Hide schema")

            Circle().fill(statusColor).frame(width: 8, height: 8)
                .help(model.isConnected ? "Connected" : "Not connected")

            Picker("", selection: $model.selectedID) {
                Text("Select…").tag(UUID?.none)
                ForEach(model.connections, id: \.id) { c in
                    Text("\(c.name) (\(c.kind.displayName))").tag(UUID?.some(c.id))
                }
            }
            .labelsHidden().fixedSize()
            .onChange(of: model.selectedID) { Task { await model.connectSelected() } }

            SQLDatabasePicker(model: model)
            SQLSchemaPicker(model: model)

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

            Spacer()

            Button("Run  ⌘↵") { Task { await model.runQuery() } }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.isConnected)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private var statusColor: Color {
        if model.isConnecting { return DT.accentAmber }
        return model.isConnected ? DT.accentGreen : DT.textFaint
    }

    // MARK: - Schema sidebar (reuses SQLSchemaBrowser)

    private var sidebar: some View {
        VStack(spacing: 0) {
            if !model.tables.isEmpty {
                SQLSchemaBrowser(
                    tables: model.tables,
                    columnsByTable: model.columnsByTable,
                    onExpand: { table in Task { await model.expand(table: table) } },
                    onPickTable: { table in model.pickTable(table) }
                )
            } else {
                Text(
                    model.isConnected
                        ? "No tables in this database yet." : "Connect to browse the schema."
                )
                .font(.system(size: 11)).foregroundColor(DT.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 8)
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// A thin draggable strip on the sidebar's trailing edge, doubling as the vertical hairline between
    /// the sidebar and the center; drags adjust the persisted width (clamped).
    private var sidebarResizeHandle: some View {
        Rectangle()
            .fill(.black.opacity(0.16))
            .frame(width: 1)
            .frame(width: 6)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        layout.sidebarWidth = layout.clampedSidebarWidth(layout.sidebarWidth + value.translation.width)
                    }
            )
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
    }

    // MARK: - Center: editor over results (draggable vertical split)

    private func center(totalHeight: CGFloat) -> some View {
        let editorHeight = max(0, totalHeight * layout.editorSplitFraction)
        return VStack(spacing: 0) {
            SQLQueryEditor(model: model)
                .frame(height: editorHeight)
            splitHandle(totalHeight: totalHeight)
            SQLResultsView(
                result: model.result,
                editable: model.editable,
                foreignKeyMatches: model.foreignKeyMatches,
                onCommit: { staged in await SQLEditCommit.commit(staged, model: model) },
                onNavigateForeignKey: { match, value in
                    await model.navigateForeignKey(
                        referencedTable: match.referencedTable,
                        referencedColumn: match.referencedColumn, value: value)
                },
                statementResults: model.results,
                selectedResultIndex: model.selectedResultIndex,
                onSelectResult: { model.selectResult($0) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// A draggable horizontal divider between editor and results; drags adjust the persisted fraction.
    private func splitHandle(totalHeight: CGFloat) -> some View {
        ThemedDivider()
            .frame(height: 6)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        guard totalHeight > 0 else { return }
                        let delta = value.translation.height / totalHeight
                        layout.editorSplitFraction = layout.clampedEditorSplitFraction(
                            layout.editorSplitFraction + delta)
                    }
            )
            .onHover { hovering in
                if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
    }
}
