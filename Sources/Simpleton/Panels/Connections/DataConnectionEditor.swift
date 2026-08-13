// Sources/Simpleton/Panels/Connections/DataConnectionEditor.swift
import SimpletonCore
import SwiftUI

/// Add/edit sheet for a data connection: kind + fields, color, group, tags, and an optional
/// SSH-bookmark tunnel reference. Secrets go to the Keychain via the caller.
struct DataConnectionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var themeSettings = ThemeSettings.shared
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
    @State private var identityFile = ""
    @State private var passphrase = ""
    @State private var color: String?
    @State private var group = ""
    @State private var tagsText = ""
    @State private var tunnelBookmarkID: UUID?
    @State private var didLoad = false

    private let kinds: [ConnectionKind] = [.postgres, .mysql, .sqlite, .sftp]

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
            } else if kind == .sftp {
                HStack {
                    TextField("Host", text: $host).textFieldStyle(.roundedBorder)
                    TextField("Port", text: $port).textFieldStyle(.roundedBorder).frame(width: 80)
                }
                TextField("User", text: $username).textFieldStyle(.roundedBorder)
                SecureField(passwordPlaceholder, text: $password).textFieldStyle(.roundedBorder)
                HStack {
                    TextField("Identity file (optional)", text: $identityFile)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…") { chooseIdentityFile() }
                }
                SecureField(
                    existing == nil ? "Passphrase (optional)" : "Passphrase (blank = unchanged)",
                    text: $passphrase
                )
                .textFieldStyle(.roundedBorder)
                tunnelPicker
            } else {
                HStack {
                    TextField("Host", text: $host).textFieldStyle(.roundedBorder)
                    TextField("Port", text: $port).textFieldStyle(.roundedBorder).frame(width: 80)
                }
                TextField("Database", text: $database).textFieldStyle(.roundedBorder)
                TextField("User", text: $username).textFieldStyle(.roundedBorder)
                SecureField(passwordPlaceholder, text: $password).textFieldStyle(.roundedBorder)
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
        .background(DT.base)  // theme the sheet with the active appearance, matching the app chrome
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

    /// SFTP allows key-only auth, so its password is optional; the SQL kinds require a password.
    private var passwordPlaceholder: String {
        let optional = kind == .sftp
        if existing == nil { return optional ? "Password (optional)" : "Password" }
        return "Password (blank = unchanged)"
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
        identityFile = c.params["identityFile"] ?? ""
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

    private func chooseIdentityFile() {
        let p = NSOpenPanel()
        p.canChooseFiles = true
        p.canChooseDirectories = false
        p.allowsMultipleSelection = false
        p.showsHiddenFiles = true  // SSH keys live in the hidden ~/.ssh directory
        p.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        if p.runModal() == .OK, let url = p.url { identityFile = url.path }
    }

    private func save() {
        var params: [String: String] = [:]
        switch kind {
        case .sqlite:
            params["path"] = sqlitePath
        case .sftp:
            let trimmed = identityFile.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { params["identityFile"] = trimmed }
        default:
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
        let secret = buildSecret()
        onSave(connection, secret)
        dismiss()
    }

    /// Build the Keychain secret for the current kind: SQLite has none; SFTP carries an optional
    /// password and/or passphrase; the SQL server kinds carry a password. Empty fields → nil so an
    /// edit that leaves a secret blank does not overwrite the stored value.
    private func buildSecret() -> ConnectionSecret? {
        switch kind {
        case .sqlite:
            return nil
        case .sftp:
            let pw = password.isEmpty ? nil : password
            let pp = passphrase.isEmpty ? nil : passphrase
            guard pw != nil || pp != nil else { return nil }
            return ConnectionSecret(password: pw, passphrase: pp)
        default:
            return password.isEmpty ? nil : ConnectionSecret(password: password)
        }
    }
}
