# Connection Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A "Data Connections" bookmark/manager (colors, groups, tags, tunnel-through-SSH) for the client viewers, built on the Phase 0 `Connection` foundation and mirroring the SSH connections sidebar.

**Architecture:** Extend `Connection` with `color`/`group`/`tunnelBookmarkID` (optional, tolerant-decoded) + `ConnectionStore.groups()`/`byGroup(_:)`. Build a `DataConnectionsPanel` (SwiftUI, mirroring `SidebarView`) + a `DataConnectionEditor` sheet (extending `SQLConnectionEditor`), registered as a left panel. A `ConnectionLaunch { .gui, .text }` seam launches a connection; `.gui` reveals the SQL panel via a notification, `.text` is stubbed for sub-project 2.

**Tech Stack:** Swift 6 / SPM (no Xcode), AppKit + SwiftUI-in-`NSHostingController`, `CoreChecks` runner.

**Spec:** `docs/design/2026-08-13-connection-manager.md`

## Global Constraints

- Build `swift build`; check `swift run CoreChecks`; lint `swift format lint --recursive --parallel --strict Sources Tests` (exit 0). Auto-fix with `swift format --in-place --recursive Sources Tests`.
- Codable stays **tolerant** (`decodeIfPresent`, missing keys → defaults). `Connection`'s `CodingKeys` + `encode` are synthesized — new stored properties extend both automatically; only `init(from:)` needs new `decodeIfPresent` lines.
- **SSH `Bookmark`/`BookmarkStore`/`KeychainManager` untouched.** The tunnel is a **reference** (`tunnelBookmarkID`); no SSH secret is copied.
- Secrets stay in `CredentialStore` (Keychain); only metadata in `connections.json`.
- Mirror `SidebarView`'s structure/tokens precisely (`DT`, `themedGlass`, `ThemedDivider`, `SidebarSectionHeader`).
- Conventional commits, **no co-author, no Claude/AI mention**.
- **Non-goals (sub-project 2):** nested groups, inline tunnels, launcher placement, the text-client CLI pane. `.text` is a logged stub here.

## Integration facts (verified verbatim)

- `Connection` (`Sources/SimpletonCore/Models/Connection.swift`): struct props end at `updatedAt`; memberwise `init` ends `updatedAt: Date = Date()`; tolerant `init(from:)` uses `c.decodeIfPresent(...)`. `ConnectionKind.icon`/`displayName`/`defaultPort` exist.
- `ConnectionStore` actor has `all()/byKind(_:)/pinned()/connection(for:)/search(query:)/add/update/delete`; posts `.simpletonConnectionsChanged`.
- `BookmarkStore` actor: `allBookmarks() -> [Bookmark]`; `Bookmark` has `id: UUID`, `name`, `host`.
- `CredentialStore`: `store(_:for:) -> Bool`, `secret(for:) -> ConnectionSecret?`, `delete(for:) -> Bool`, `has(id:)`.
- `PanelContext` exposes `appSupportDir: URL` and `bookmarkStore: BookmarkStore?`.
- `SidebarSectionHeader(title:)`, `GhostButtonStyle`, `SidebarRow` live in `SidebarView.swift`; `SidebarHostController(bookmarkStore:sshConfigWatcher:config:)` wraps it; `BuiltInPanels.connections` builds it.
- Panels register in `AppDelegate` (~line 162, after `.sql`) and are `static let` on `extension PanelDefinition` in `BuiltInPanels.swift`; ids in `PanelProfile.PanelID`.
- `SQLPanelModel(appSupportDir:)` has `@Published selectedID`, `reload()`, `connect()`, `connections`.

---

## File Structure

**Modify**
- `Sources/SimpletonCore/Models/Connection.swift` — add `color`/`group`/`tunnelBookmarkID` (struct + init + decode).
- `Sources/SimpletonCore/Core/ConnectionStore.swift` — add `groups()`/`byGroup(_:)`.
- `Sources/Simpleton/Panels/SQL/SQLPanelModel.swift` — add `openConnection(id:)`.
- `Sources/Simpleton/Panels/SQL/SQLPanelView.swift` — observe `.simpletonOpenConnectionGUI`.
- `Sources/Simpleton/Panels/BuiltInPanels.swift` — register `dataConnections`.
- `Sources/Simpleton/Panels/PanelProfile.swift` — `PanelID.dataConnections` + add to Developer profile's `leftPanelIDs`.
- `Sources/Simpleton/AppDelegate.swift` — `register(.dataConnections)`.
- `Tests/CoreChecks/ConnectionChecks.swift` — extend model + store checks.

**Create**
- `Sources/Simpleton/Panels/Connections/ConnectionColor.swift` — name→`Color` swatch mapping + `ConnectionLaunch` + `.simpletonOpenConnectionGUI`.
- `Sources/Simpleton/Panels/Connections/DataConnectionRow.swift`
- `Sources/Simpleton/Panels/Connections/DataConnectionEditor.swift`
- `Sources/Simpleton/Panels/Connections/DataConnectionsPanel.swift` — model + view.
- `Sources/Simpleton/Panels/Connections/DataConnectionsHostController.swift`

---

## Task 1: `Connection` model additions + checks

**Files:** Modify `Sources/SimpletonCore/Models/Connection.swift`, `Tests/CoreChecks/ConnectionChecks.swift`.

**Interfaces produced:** `Connection.color: String?`, `.group: String?`, `.tunnelBookmarkID: UUID?` (memberwise-init params after `updatedAt`, all default `nil`; tolerant-decoded).

- [ ] **Step 1: Add the three stored properties**

In `Connection`, after `public var updatedAt: Date`:
```swift
    /// Env-safety accent, one of the app accent names (red/orange/yellow/green/blue/purple/pink/graphite).
    /// Convention: prod = red. Nil = no color.
    public var color: String?
    /// Single-level group name (e.g. "prod"). Nil = ungrouped. Nested groups are a later enhancement.
    public var group: String?
    /// References an SSH `Bookmark` (by id) to tunnel this connection through a bastion. Nil = direct.
    public var tunnelBookmarkID: UUID?
```

- [ ] **Step 2: Extend the memberwise init**

Change the init parameter list ending (`… updatedAt: Date = Date()`) to append three params, and add their assignments:
```swift
        updatedAt: Date = Date(),
        color: String? = nil,
        group: String? = nil,
        tunnelBookmarkID: UUID? = nil
    ) {
        // … existing assignments …
        self.updatedAt = updatedAt
        self.color = color
        self.group = group
        self.tunnelBookmarkID = tunnelBookmarkID
    }
```

- [ ] **Step 3: Extend the tolerant decoder**

In `init(from:)`, after the `updatedAt = …` line:
```swift
        color = try c.decodeIfPresent(String.self, forKey: .color)
        group = try c.decodeIfPresent(String.self, forKey: .group)
        tunnelBookmarkID = try c.decodeIfPresent(UUID.self, forKey: .tunnelBookmarkID)
```
(`CodingKeys` and `encode` are synthesized — the new properties are included automatically.)

- [ ] **Step 4: Add model checks**

In `Tests/CoreChecks/ConnectionChecks.swift`, add a suite inside `runConnectionChecks` (after the existing round-trip suite):
```swift
    t.suite("Connection new fields round-trip + tolerant legacy decode") {
        let full = Connection(
            name: "prod-db", kind: .postgres, host: "db", port: 5432, username: "app",
            params: ["database": "app"], tags: ["prod"], pinned: true,
            color: "red", group: "prod", tunnelBookmarkID: UUID())
        do {
            let data = try JSONEncoder().encode(full)
            let decoded = try JSONDecoder().decode(Connection.self, from: data)
            t.expectEqual(decoded, full, "full connection with color/group/tunnel round-trips")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
        // Legacy record (no new keys) → new fields default nil.
        let legacy = #"{"id":"22222222-2222-2222-2222-222222222222","name":"old","kind":"mysql"}"#
        do {
            let d = try JSONDecoder().decode(Connection.self, from: Data(legacy.utf8))
            t.expect(d.color == nil, "color defaults nil")
            t.expect(d.group == nil, "group defaults nil")
            t.expect(d.tunnelBookmarkID == nil, "tunnelBookmarkID defaults nil")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }
```

- [ ] **Step 5: Verify + commit**

Run: `swift build 2>&1 | tail -1` → `Build complete!`; `swift run CoreChecks 2>&1 | tail -1` → all pass.
```bash
swift format lint --recursive --parallel --strict Sources Tests || swift format --in-place --recursive Sources Tests
git add Sources/SimpletonCore/Models/Connection.swift Tests/CoreChecks/ConnectionChecks.swift
git commit -m "feat(connections): add color, group, and tunnel-reference fields"
```

---

## Task 2: `ConnectionStore.groups()` + `byGroup(_:)` + checks

**Files:** Modify `Sources/SimpletonCore/Core/ConnectionStore.swift`, `Tests/CoreChecks/ConnectionChecks.swift`.

**Interfaces produced:** `func groups() -> [String]` (distinct, sorted), `func byGroup(_ group: String) -> [Connection]` (name-sorted).

- [ ] **Step 1: Add the methods**

In `ConnectionStore`, after `search(query:)`:
```swift
    /// Distinct non-nil group names, sorted.
    public func groups() -> [String] {
        try? ensureLoaded()
        return Array(Set(connections.values.compactMap { $0.group })).sorted()
    }

    /// Connections in a given group, sorted by name.
    public func byGroup(_ group: String) -> [Connection] {
        try? ensureLoaded()
        return connections.values.filter { $0.group == group }.sorted { $0.name < $1.name }
    }
```

- [ ] **Step 2: Add store checks**

In `runConnectionStoreChecks` (async), add a suite:
```swift
    await t.suite("ConnectionStore groups() / byGroup / new-field persistence") {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            let store = ConnectionStore(directory: dir)
            try await store.add(Connection(name: "a", kind: .postgres, group: "prod", color: "red"))
            try await store.add(Connection(name: "b", kind: .mysql, group: "prod"))
            try await store.add(Connection(name: "c", kind: .sqlite))  // ungrouped
            t.expectEqual(await store.groups(), ["prod"], "distinct sorted groups")
            t.expectEqual(await store.byGroup("prod").count, 2, "two in prod")
            // New fields persist across instances.
            let s2 = ConnectionStore(directory: dir)
            try await s2.load()
            let a = await s2.all().first { $0.name == "a" }
            t.expectEqual(a?.color, "red", "color persisted")
            t.expectEqual(a?.group, "prod", "group persisted")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }
```
(`makeTempDir()` is already defined at the top of `runConnectionStoreChecks`.)

- [ ] **Step 3: Verify + commit**

`swift build` → complete; `swift run CoreChecks` → all pass.
```bash
swift format lint --recursive --parallel --strict Sources Tests || swift format --in-place --recursive Sources Tests
git add Sources/SimpletonCore/Core/ConnectionStore.swift Tests/CoreChecks/ConnectionChecks.swift
git commit -m "feat(connections): add ConnectionStore.groups() and byGroup(_:)"
```

---

## Task 3: `ConnectionColor` + `DataConnectionEditor`

**Files:** Create `Sources/Simpleton/Panels/Connections/ConnectionColor.swift`, `Sources/Simpleton/Panels/Connections/DataConnectionEditor.swift`.

**Interfaces produced:** `enum ConnectionColor` (`names: [String]`, `swatch(_:) -> Color`); `enum ConnectionLaunch { case gui, text }`; `Notification.Name.simpletonOpenConnectionGUI`; `DataConnectionEditor(bookmarks:existingGroups:existing:onSave:)`.

- [ ] **Step 1: Color + launch seam file**

Create `ConnectionColor.swift`:
```swift
// Sources/Simpleton/Panels/Connections/ConnectionColor.swift
import SwiftUI

/// The env-safety color palette for data connections — the app's 8 accent names → SwiftUI colors.
enum ConnectionColor {
    static let names = ["red", "orange", "yellow", "green", "blue", "purple", "pink", "graphite"]

    static func swatch(_ name: String?) -> Color {
        switch name {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "graphite": return Color(nsColor: .systemGray)
        default: return DT.textFaint
        }
    }
}

/// How a connection is launched from the manager.
enum ConnectionLaunch { case gui, text }

extension Notification.Name {
    /// Posted (object = connection `id: UUID`) to ask the SQL panel to open that connection.
    static let simpletonOpenConnectionGUI = Notification.Name("simpletonOpenConnectionGUI")
}
```

- [ ] **Step 2: The editor**

Create `DataConnectionEditor.swift` (extends the SQL editor with color/group/tags/tunnel + edit mode):
```swift
// Sources/Simpleton/Panels/Connections/DataConnectionEditor.swift
import SimpletonCore
import SwiftUI

/// Add/edit sheet for a data connection: kind + fields, color, group, tags, and an optional
/// SSH-bookmark tunnel reference. Secrets go to the Keychain via the caller.
struct DataConnectionEditor: View {
    @Environment(\.dismiss) private var dismiss
    let bookmarks: [Bookmark]
    let existingGroups: [String]
    let existing: Connection?
    let onSave: (Connection, ConnectionSecret?) -> Void

    @State private var kind: ConnectionKind = .postgres
    @State private var name = ""
    @State private var host = "localhost"
    @State private var port = ""
    @State private var username = ""
    @State private var password = ""
    @State private var database = ""
    @State private var sqlitePath = ""
    @State private var useTLS = false
    @State private var color: String?
    @State private var group = ""
    @State private var tagsText = ""
    @State private var tunnelBookmarkID: UUID?
    @State private var didLoad = false

    private let kinds: [ConnectionKind] = [.postgres, .mysql, .sqlite]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(existing == nil ? "New Connection" : "Edit Connection")
                .font(.headline).foregroundColor(DT.textPrimary)
            Picker("Type", selection: $kind) {
                ForEach(kinds, id: \.self) { Text($0.displayName).tag($0) }
            }
            .onChange(of: kind) { if port.isEmpty, let p = kind.defaultPort { port = String(p) } }
            TextField("Name", text: $name).textFieldStyle(.roundedBorder)

            if kind == .sqlite {
                HStack {
                    TextField("Database file path", text: $sqlitePath).textFieldStyle(.roundedBorder)
                    Button("Choose…") { chooseFile() }
                }
            } else {
                HStack {
                    TextField("Host", text: $host).textFieldStyle(.roundedBorder)
                    TextField("Port", text: $port).textFieldStyle(.roundedBorder).frame(width: 80)
                }
                TextField("Database", text: $database).textFieldStyle(.roundedBorder)
                TextField("User", text: $username).textFieldStyle(.roundedBorder)
                SecureField(existing == nil ? "Password" : "Password (blank = unchanged)", text: $password)
                    .textFieldStyle(.roundedBorder)
                Toggle("Use TLS", isOn: $useTLS)
                tunnelPicker
            }

            colorPicker
            groupField
            TextField("Tags (comma-separated)", text: $tagsText).textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(name.isEmpty)
            }
        }
        .padding(16).frame(width: 400)
        .onAppear(perform: loadExisting)
    }

    private var colorPicker: some View {
        HStack(spacing: 6) {
            Text("Color").font(.system(size: 12)).foregroundColor(DT.textSecondary)
            ForEach(ConnectionColor.names, id: \.self) { n in
                Circle().fill(ConnectionColor.swatch(n)).frame(width: 16, height: 16)
                    .overlay(Circle().stroke(DT.textPrimary, lineWidth: color == n ? 2 : 0))
                    .onTapGesture { color = (color == n ? nil : n) }
            }
            Spacer()
        }
    }

    private var groupField: some View {
        HStack {
            TextField("Group", text: $group).textFieldStyle(.roundedBorder)
            if !existingGroups.isEmpty {
                Menu {
                    ForEach(existingGroups, id: \.self) { g in Button(g) { group = g } }
                } label: { Image(systemName: "chevron.down") }.fixedSize()
            }
        }
    }

    private var tunnelPicker: some View {
        HStack {
            Text("Tunnel").font(.system(size: 12)).foregroundColor(DT.textSecondary)
            Menu {
                Button("None") { tunnelBookmarkID = nil }
                ForEach(bookmarks) { b in Button(b.name) { tunnelBookmarkID = b.id } }
            } label: {
                Text(tunnelName).font(.system(size: 12))
            }
            Spacer()
        }
    }

    private var tunnelName: String {
        if let id = tunnelBookmarkID, let b = bookmarks.first(where: { $0.id == id }) { return "via \(b.name)" }
        return "None"
    }

    private func loadExisting() {
        guard !didLoad else { return }
        didLoad = true
        guard let c = existing else { return }
        kind = c.kind
        name = c.name
        host = c.host ?? "localhost"
        port = c.port.map(String.init) ?? ""
        username = c.username ?? ""
        database = c.params["database"] ?? ""
        sqlitePath = c.params["path"] ?? ""
        useTLS = c.params["useTLS"] == "true"
        color = c.color
        group = c.group ?? ""
        tagsText = c.tags.joined(separator: ", ")
        tunnelBookmarkID = c.tunnelBookmarkID
    }

    private func chooseFile() {
        let p = NSOpenPanel()
        p.canChooseFiles = true
        p.canChooseDirectories = false
        p.allowsMultipleSelection = false
        if p.runModal() == .OK, let url = p.url { sqlitePath = url.path }
    }

    private func save() {
        var params: [String: String] = [:]
        if kind == .sqlite {
            params["path"] = sqlitePath
        } else {
            params["database"] = database
            params["useTLS"] = useTLS ? "true" : "false"
        }
        let tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let connection = Connection(
            id: existing?.id ?? UUID(),
            name: name, kind: kind,
            host: kind == .sqlite ? nil : host,
            port: kind == .sqlite ? nil : Int(port),
            username: kind == .sqlite ? nil : username,
            params: params, tags: tags, pinned: existing?.pinned ?? false,
            createdAt: existing?.createdAt ?? Date(),
            color: color, group: group.isEmpty ? nil : group,
            tunnelBookmarkID: kind == .sqlite ? nil : tunnelBookmarkID)
        let secret = (kind == .sqlite || password.isEmpty) ? nil : ConnectionSecret(password: password)
        onSave(connection, secret)
        dismiss()
    }
}
```

- [ ] **Step 3: Build + lint + commit**

`swift build 2>&1 | tail -1` → `Build complete!` (no errors in the new files).
```bash
swift format lint --recursive --parallel --strict Sources Tests || swift format --in-place --recursive Sources Tests
git add Sources/Simpleton/Panels/Connections/ConnectionColor.swift Sources/Simpleton/Panels/Connections/DataConnectionEditor.swift
git commit -m "feat(connections): add color palette, launch seam, and connection editor"
```

---

## Task 4: `DataConnectionsPanel` (model + view + row + host)

**Files:** Create `DataConnectionRow.swift`, `DataConnectionsPanel.swift`, `DataConnectionsHostController.swift`.

**Interfaces produced:** `DataConnectionsModel(appSupportDir:bookmarkStore:onLaunch:)`; `DataConnectionsPanel(model:)`; `DataConnectionRow(connection:onTap:)`; `DataConnectionsHostController(appSupportDir:bookmarkStore:onLaunch:)`.

- [ ] **Step 1: The row**

Create `DataConnectionRow.swift` (mirrors `SidebarRow` + color dot + kind icon + tag chip):
```swift
// Sources/Simpleton/Panels/Connections/DataConnectionRow.swift
import SimpletonCore
import SwiftUI

struct DataConnectionRow: View {
    let connection: Connection
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Circle().fill(ConnectionColor.swatch(connection.color)).frame(width: 8, height: 8)
                Image(systemName: connection.kind.icon)
                    .font(.system(size: 10)).foregroundColor(DT.textMuted).frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(connection.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(isHovered ? DT.textPrimary : DT.textSecondary).lineLimit(1)
                        if connection.pinned {
                            Image(systemName: "star.fill").font(.system(size: 8)).foregroundColor(DT.accentAmber)
                        }
                    }
                    Text(subtitle).font(DT.monoFont(size: 10)).foregroundColor(DT.textMuted).lineLimit(1)
                }
                Spacer()
                if let tag = connection.tags.first {
                    Text(tag)
                        .font(.system(size: 8, weight: .medium)).foregroundColor(DT.textFaint)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(DT.textFaint.opacity(0.15)).cornerRadius(DT.radiusPill)
                }
            }
            .padding(.vertical, 6).padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: DT.radiusButton, style: .continuous)
                    .fill(isHovered ? DT.hover : Color.clear))
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(DT.hoverAnimation) { isHovered = h } }
    }

    private var subtitle: String {
        if let host = connection.host { return host }
        if connection.kind == .sqlite, let p = connection.params["path"] { return (p as NSString).lastPathComponent }
        return connection.kind.displayName
    }
}
```

- [ ] **Step 2: The model + view**

Create `DataConnectionsPanel.swift`:
```swift
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

    init(appSupportDir: URL, bookmarkStore: BookmarkStore?, onLaunch: @escaping (Connection, ConnectionLaunch) -> Void) {
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
        let copy = Connection(
            name: connection.name + " copy", kind: connection.kind, host: connection.host,
            port: connection.port, username: connection.username, params: connection.params,
            tags: connection.tags, pinned: false, color: connection.color, group: connection.group,
            tunnelBookmarkID: connection.tunnelBookmarkID)
        try? await store.add(copy)
        await reload()
    }

    func beginAdd() { editing = nil; showingEditor = true }
    func beginEdit(_ c: Connection) { editing = c; showingEditor = true }
}

struct DataConnectionsPanel: View {
    @StateObject var model: DataConnectionsModel
    @ObservedObject private var themeSettings = ThemeSettings.shared

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
                Section { ForEach(model.pinned) { row($0) } } header: { SidebarSectionHeader(title: "Pinned") }
            }
            ForEach(model.grouped, id: \.group) { grp in
                Section { ForEach(grp.items) { row($0) } } header: { SidebarSectionHeader(title: grp.group) }
            }
            if !model.ungrouped.isEmpty {
                Section { ForEach(model.ungrouped) { row($0) } } header: { SidebarSectionHeader(title: "Ungrouped") }
            }
        }
        .listStyle(.sidebar).scrollContentBackground(.hidden)
        .tint(themeSettings.accent).environment(\.defaultMinListRowHeight, 34)
    }

    private func row(_ c: Connection) -> some View {
        DataConnectionRow(connection: c, onTap: { model.onLaunch(c, .gui) })
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
            .overlay(RoundedRectangle(cornerRadius: DT.radiusCard).stroke(DT.border.opacity(0.5), lineWidth: 1))
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
```

- [ ] **Step 3: The host controller**

Create `DataConnectionsHostController.swift` (mirrors `SidebarHostController`):
```swift
// Sources/Simpleton/Panels/Connections/DataConnectionsHostController.swift
import AppKit
import SimpletonCore
import SwiftUI

/// Hosts the SwiftUI DataConnectionsPanel for embedding in the AppKit panel split.
final class DataConnectionsHostController: NSViewController {
    private let appSupportDir: URL
    private let bookmarkStore: BookmarkStore?
    private let onLaunch: (Connection, ConnectionLaunch) -> Void

    init(appSupportDir: URL, bookmarkStore: BookmarkStore?, onLaunch: @escaping (Connection, ConnectionLaunch) -> Void) {
        self.appSupportDir = appSupportDir
        self.bookmarkStore = bookmarkStore
        self.onLaunch = onLaunch
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let model = DataConnectionsModel(
            appSupportDir: appSupportDir, bookmarkStore: bookmarkStore, onLaunch: onLaunch)
        self.view = NSHostingView(rootView: DataConnectionsPanel(model: model))
        self.view.frame = NSRect(x: 0, y: 0, width: 240, height: 600)
    }
}
```

- [ ] **Step 4: Build + lint + commit**

`swift build 2>&1 | tail -1` → `Build complete!`.
```bash
swift format lint --recursive --parallel --strict Sources Tests || swift format --in-place --recursive Sources Tests
git add Sources/Simpleton/Panels/Connections/DataConnectionRow.swift Sources/Simpleton/Panels/Connections/DataConnectionsPanel.swift Sources/Simpleton/Panels/Connections/DataConnectionsHostController.swift
git commit -m "feat(connections): add Data Connections manager panel"
```

---

## Task 5: Register panel + wire the `.gui` launch to the SQL panel

**Files:** Modify `BuiltInPanels.swift`, `PanelProfile.swift`, `AppDelegate.swift`, `SQLPanelModel.swift`, `SQLPanelView.swift`.

**Interfaces consumed:** `DataConnectionsHostController`, `ConnectionLaunch`, `.simpletonOpenConnectionGUI` (Task 3/4); `PanelContext.appSupportDir`/`bookmarkStore`.

- [ ] **Step 1: `SQLPanelModel.openConnection(id:)`**

In `SQLPanelModel`, add:
```swift
    /// Open a specific connection by id (from the Data Connections manager): select it and connect.
    func openConnection(id: UUID) async {
        await reload()
        if connections.contains(where: { $0.id == id }) {
            selectedID = id
            await connect()
        }
    }
```

- [ ] **Step 2: Observe the notification in `SQLPanelView`**

In `SQLPanelView.body`, add a modifier on the `ClientPanelScaffold(...) { … }` (alongside the existing `.sheet`):
```swift
        .onReceive(NotificationCenter.default.publisher(for: .simpletonOpenConnectionGUI)) { note in
            if let id = note.object as? UUID { Task { await model.openConnection(id: id) } }
        }
```

- [ ] **Step 3: Register the panel + id**

`PanelProfile.swift` — add to `PanelID`:
```swift
        static let dataConnections = "data-connections"
```
Add `"data-connections"` to the **Developer** profile's `leftPanelIDs` (before `"processes"`):
```swift
                "connections", "data-connections", "snippets", "notes", "history", "environment",
                "file-browser", "processes", "ssh-tunnels",
```

`BuiltInPanels.swift` — add a definition (after `sql`):
```swift
    static let dataConnections = PanelDefinition(
        id: PanelProfile.PanelID.dataConnections,
        name: "Data Connections",
        icon: "bookmark.fill",
        description: "Saved database & service connections",
        defaultSide: .left,
        isBuiltIn: true
    ) { context in
        DataConnectionsHostController(
            appSupportDir: context.appSupportDir,
            bookmarkStore: context.bookmarkStore,
            onLaunch: { connection, mode in
                switch mode {
                case .gui:
                    // Notify the SQL panel (if mounted) to open this connection. Reliable reveal/
                    // docking arrives in workbench sub-project 2; deferred post lets a just-activated
                    // panel mount first.
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .simpletonOpenConnectionGUI, object: connection.id)
                    }
                case .text:
                    NSLog("SIMP: text client for %@ — implemented in workbench sub-project 2", connection.name)
                }
            })
    }
```

`AppDelegate.swift` — after `panelRegistry.register(.sql)`:
```swift
        panelRegistry.register(.dataConnections)
```

- [ ] **Step 4: Build + verify + manual**

`swift build 2>&1 | tail -1` → `Build complete!`; `swift run CoreChecks 2>&1 | tail -1` → all pass (no regression).
Manual: launch, switch to the Developer profile, open **Data Connections** (left rail); ＋ Add a SQLite connection with a **color** and **group**; confirm it appears under its group with the color dot; edit/duplicate/pin/delete via context menu; with the SQL panel also open, clicking a connection selects + connects it in the SQL panel.

- [ ] **Step 5: Lint + commit**

```bash
swift format lint --recursive --parallel --strict Sources Tests || swift format --in-place --recursive Sources Tests
git add Sources/Simpleton/Panels/BuiltInPanels.swift Sources/Simpleton/Panels/PanelProfile.swift Sources/Simpleton/AppDelegate.swift Sources/Simpleton/Panels/SQL/SQLPanelModel.swift Sources/Simpleton/Panels/SQL/SQLPanelView.swift
git commit -m "feat(connections): register Data Connections panel and wire GUI launch to SQL"
```

---

## Task 6: Final verification

**Files:** none.

- [ ] **Step 1:** `swift build 2>&1 | tail -1` → `Build complete!`
- [ ] **Step 2:** `swift run CoreChecks 2>&1 | tail -1` → all pass (model + store suites present).
- [ ] **Step 3:** `swift format lint --recursive --parallel --strict Sources Tests` → exit 0.
- [ ] **Step 4:** `bash scripts/e2e/workspace-e2e.sh` → `SIMP-WSE2E RESULT PASS`.

---

## Self-Review

**Spec coverage**
- §2 model additions (`color`/`group`/`tunnelBookmarkID`, tolerant) → Task 1.
- §3 store `groups()`/`byGroup(_:)` → Task 2.
- §4 management UI (sections Pinned→per-group→Ungrouped, color-dot/kind-icon/name/tags row, search, ＋Add, refresh, context menu) → Task 4; §4 editor (color/group/tags/tunnel picker) → Task 3.
- §5 launch seam (`ConnectionLaunch`, `.gui`→SQL via `.simpletonOpenConnectionGUI`, `.text` stub) → Tasks 3+5.
- §6 security (secrets in Keychain; tunnel is a reference) → editor/model store only metadata + `tunnelBookmarkID`; no SSH secret copied.
- §7 testing → Tasks 1–2 checks + Task 6 gate.
- §8 registration → Task 5. Non-goals (nested groups, inline tunnel, launcher placement, text CLI) excluded.

**Placeholder scan:** none — every code step is complete source; the `.text` `NSLog` is an intentional, spec-mandated stub.

**Type consistency:** `Connection(… color:group:tunnelBookmarkID:)` order matches Task 1's init across Task 3/4 call sites. `ConnectionColor.swatch(_:)`/`.names`, `ConnectionLaunch`, `.simpletonOpenConnectionGUI` defined in Task 3, used in Tasks 4–5. `DataConnectionsModel(appSupportDir:bookmarkStore:onLaunch:)` identical in Task 4 host + Task 5 registration. `SQLPanelModel.openConnection(id:)` defined Task 5 Step 1, called Step 2. `ConnectionStore.groups()`/`byGroup(_:)` defined Task 2, used by `DataConnectionsModel.reload()` (Task 4). `SidebarSectionHeader`/`GhostButtonStyle` reused from `SidebarView.swift` (same target).
