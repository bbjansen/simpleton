// Sources/Simpleton/Panels/Connections/DataConnectionsPanel.swift
import AppKit
import SimpletonCore
import SwiftUI

@MainActor
final class DataConnectionsModel: ObservableObject {
    @Published var pinned: [Connection] = []
    @Published var grouped: [(group: String, items: [Connection])] = []
    @Published var ungrouped: [Connection] = []
    @Published var searchText: String = ""
    @Published var bookmarks: [Bookmark] = []
    @Published var allGroups: [String] = []
    @Published var showingEditor = false
    @Published var editing: Connection?

    private let store: ConnectionStore
    private let bookmarkStore: BookmarkStore?
    let onLaunch: (Connection, ConnectionLaunch) -> Void

    init(
        appSupportDir: URL, bookmarkStore: BookmarkStore?,
        onLaunch: @escaping (Connection, ConnectionLaunch) -> Void
    ) {
        self.store = ConnectionStore(directory: appSupportDir)
        self.bookmarkStore = bookmarkStore
        self.onLaunch = onLaunch
    }

    var isEmpty: Bool { pinned.isEmpty && grouped.isEmpty && ungrouped.isEmpty }

    func reload() async {
        let all = searchText.isEmpty ? await store.all() : await store.search(query: searchText)
        pinned = all.filter(\.pinned)
        let rest = all.filter { !$0.pinned }
        let groups = Array(Set(rest.compactMap { $0.group })).sorted()
        grouped = groups.map { g in (g, rest.filter { $0.group == g }) }
        ungrouped = rest.filter { $0.group == nil }
        allGroups = await store.groups()
        if let bs = bookmarkStore { bookmarks = await bs.allBookmarks() }
    }

    func save(_ connection: Connection, secret: ConnectionSecret?) async {
        if await store.connection(for: connection.id) != nil {
            try? await store.update(connection)
        } else {
            try? await store.add(connection)
        }
        if let secret { CredentialStore.store(secret, for: connection.id) }
        await reload()
    }

    func delete(_ connection: Connection) async {
        try? await store.delete(id: connection.id)
        CredentialStore.delete(for: connection.id)
        await reload()
    }

    func togglePin(_ connection: Connection) async {
        var c = connection
        c.pinned.toggle()
        try? await store.update(c)
        await reload()
    }

    func duplicate(_ connection: Connection) async {
        let newID = UUID()
        let copy = Connection(
            id: newID, name: connection.name + " copy", kind: connection.kind, host: connection.host,
            port: connection.port, username: connection.username, params: connection.params,
            tags: connection.tags, pinned: false, color: connection.color, group: connection.group,
            tunnelBookmarkID: connection.tunnelBookmarkID)
        try? await store.add(copy)
        // Copy the stored secret so the duplicate is immediately usable (credentials are id-keyed).
        if let secret = CredentialStore.secret(for: connection.id) {
            CredentialStore.store(secret, for: newID)
        }
        await reload()
    }

    func beginAdd() {
        editing = nil
        showingEditor = true
    }

    func beginEdit(_ c: Connection) {
        editing = c
        showingEditor = true
    }
}

struct DataConnectionsPanel: View {
    @StateObject private var model: DataConnectionsModel
    @ObservedObject private var themeSettings = ThemeSettings.shared

    init(
        appSupportDir: URL, bookmarkStore: BookmarkStore?,
        onLaunch: @escaping (Connection, ConnectionLaunch) -> Void
    ) {
        _model = StateObject(
            wrappedValue: DataConnectionsModel(
                appSupportDir: appSupportDir, bookmarkStore: bookmarkStore, onLaunch: onLaunch))
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search connections", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)
                .onChange(of: model.searchText) { Task { await model.reload() } }

            if model.isEmpty {
                emptyState
            } else {
                list
            }

            Rectangle().fill(DT.border.opacity(0.5)).frame(height: 0.5)
            addButton.padding(.horizontal, 12).padding(.vertical, 10)
        }
        .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
        .themedGlass(DT.surface)
        .onAppear { Task { await model.reload() } }
        .onReceive(NotificationCenter.default.publisher(for: .simpletonConnectionsChanged)) { _ in
            Task { await model.reload() }
        }
        .sheet(isPresented: $model.showingEditor) {
            DataConnectionEditor(
                bookmarks: model.bookmarks, existingGroups: model.allGroups, existing: model.editing
            ) { conn, secret in
                Task { await model.save(conn, secret: secret) }
            }
        }
    }

    private var list: some View {
        List {
            if !model.pinned.isEmpty {
                Section {
                    ForEach(model.pinned) { row($0) }
                } header: {
                    SidebarSectionHeader(title: "Pinned")
                }
            }
            ForEach(model.grouped, id: \.group) { grp in
                Section {
                    ForEach(grp.items) { row($0) }
                } header: {
                    SidebarSectionHeader(title: grp.group)
                }
            }
            if !model.ungrouped.isEmpty {
                Section {
                    ForEach(model.ungrouped) { row($0) }
                } header: {
                    SidebarSectionHeader(title: "Ungrouped")
                }
            }
        }
        .listStyle(.sidebar).scrollContentBackground(.hidden)
        .tint(themeSettings.accent).environment(\.defaultMinListRowHeight, 34)
    }

    private func row(_ c: Connection) -> some View {
        // A kind with a registered GUI client opens that panel; anything else falls back to the
        // text-client (CLI) path instead of revealing an empty panel.
        let launch: ConnectionLaunch = GUIClientRegistry.shared.panelID(for: c.kind) != nil ? .gui : .text
        return DataConnectionRow(connection: c, onTap: { model.onLaunch(c, launch) })
            .contextMenu {
                Button(c.pinned ? "Unpin" : "Pin") { Task { await model.togglePin(c) } }
                Button("Edit") { model.beginEdit(c) }
                Button("Duplicate") { Task { await model.duplicate(c) } }
                Button("Open as Text Client") { model.onLaunch(c, .text) }
                Divider()
                Button("Delete", role: .destructive) { Task { await model.delete(c) } }
            }
    }

    private var addButton: some View {
        Button(action: { model.beginAdd() }) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle").font(.system(size: 13))
                Text("Add Connection").font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(DT.textSecondary).frame(maxWidth: .infinity).padding(.vertical, 8)
            .overlay(
                RoundedRectangle(cornerRadius: DT.radiusCard).stroke(DT.border.opacity(0.5), lineWidth: 1)
            )
            .cornerRadius(DT.radiusCard).contentShape(Rectangle())
        }
        .buttonStyle(GhostButtonStyle())
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "cylinder.split.1x2").font(.system(size: 28)).foregroundColor(DT.textFaint)
            Text("No connections yet").font(.system(size: 13, weight: .medium)).foregroundColor(DT.textMuted)
            Text("Add a database or service\nconnection to get started")
                .font(.system(size: 11)).foregroundColor(DT.textFaint).multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
