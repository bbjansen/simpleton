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
                } label: {
                    Image(systemName: "chevron.down")
                }.fixedSize()
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
        let tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter {
            !$0.isEmpty
        }
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
