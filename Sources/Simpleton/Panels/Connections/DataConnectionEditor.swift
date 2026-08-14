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
    @State private var vhost = "/"
    @State private var useTLS = false
    // S3 fields
    @State private var s3Endpoint = ""
    @State private var s3Region = "us-east-1"
    @State private var s3Bucket = ""
    @State private var s3AccessKey = ""
    @State private var s3SecretKey = ""
    @State private var s3PathStyle = true
    @State private var color: String?
    @State private var group = ""
    @State private var tagsText = ""
    @State private var tunnelBookmarkID: UUID?
    @State private var didLoad = false

    private let kinds: [ConnectionKind] = [.postgres, .mysql, .sqlite, .s3, .amqp]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(existing == nil ? "New Connection" : "Edit Connection")
                .font(.headline).foregroundColor(DT.textPrimary)
            Picker("Type", selection: $kind) {
                ForEach(kinds, id: \.self) { Text($0.displayName).tag($0) }
            }
            .onChange(of: kind) { if port.isEmpty, let p = defaultPort(for: kind) { port = String(p) } }
            TextField("Name", text: $name).textFieldStyle(.roundedBorder)

            if kind == .sqlite {
                HStack {
                    TextField("Database file path", text: $sqlitePath).textFieldStyle(.roundedBorder)
                    Button("Choose…") { chooseFile() }
                }
            } else if kind == .s3 {
                s3Fields
            } else if kind == .amqp {
                HStack {
                    TextField("Host", text: $host).textFieldStyle(.roundedBorder)
                    TextField("Port", text: $port).textFieldStyle(.roundedBorder).frame(width: 80)
                }
                TextField("Virtual host", text: $vhost).textFieldStyle(.roundedBorder)
                TextField("User", text: $username).textFieldStyle(.roundedBorder)
                SecureField(existing == nil ? "Password" : "Password (blank = unchanged)", text: $password)
                    .textFieldStyle(.roundedBorder)
                Toggle("Use TLS", isOn: $useTLS)
                tunnelPicker
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
        .background(DT.base)  // theme the sheet with the active appearance, matching the app chrome
        .onAppear(perform: loadExisting)
    }

    private var s3Fields: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Endpoint (AWS default)", text: $s3Endpoint).textFieldStyle(.roundedBorder)
            HStack {
                TextField("Region", text: $s3Region).textFieldStyle(.roundedBorder)
                TextField("Default bucket (optional)", text: $s3Bucket).textFieldStyle(.roundedBorder)
            }
            TextField("Access Key ID", text: $s3AccessKey).textFieldStyle(.roundedBorder)
            SecureField(
                existing == nil ? "Secret Access Key" : "Secret Access Key (blank = unchanged)",
                text: $s3SecretKey
            )
            .textFieldStyle(.roundedBorder)
            Toggle("Path-style addressing (MinIO / S3-compatible)", isOn: $s3PathStyle)
        }
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
        vhost = c.params["vhost"] ?? "/"
        useTLS = c.params["useTLS"] == "true"
        s3Endpoint = c.params["endpoint"] ?? ""
        s3Region = c.params["region"] ?? "us-east-1"
        s3Bucket = c.params["bucket"] ?? ""
        s3PathStyle = (c.params["pathStyle"] ?? "true") != "false"
        // Access Key ID lives in the Keychain secret alongside the secret key; load it so an edit
        // preserves it without re-typing (the secret key stays blank = unchanged).
        s3AccessKey = CredentialStore.secret(for: c.id)?.accessKey ?? ""
        color = c.color
        group = c.group ?? ""
        tagsText = c.tags.joined(separator: ", ")
        tunnelBookmarkID = c.tunnelBookmarkID
    }

    /// The port prefilled when a kind is picked. AMQP connections here target the RabbitMQ
    /// *Management HTTP API* (15672 / 15671 for TLS), not the AMQP protocol port (5672), so the
    /// editor overrides `ConnectionKind.defaultPort` for `.amqp`.
    private func defaultPort(for kind: ConnectionKind) -> Int? {
        if kind == .amqp { return useTLS ? 15671 : 15672 }
        return kind.defaultPort
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
        } else if kind == .s3 {
            params["endpoint"] = s3Endpoint.trimmingCharacters(in: .whitespaces)
            params["region"] = s3Region.trimmingCharacters(in: .whitespaces)
            params["bucket"] = s3Bucket.trimmingCharacters(in: .whitespaces)
            params["pathStyle"] = s3PathStyle ? "true" : "false"
        } else if kind == .amqp {
            params["vhost"] = vhost.isEmpty ? "/" : vhost
            params["useTLS"] = useTLS ? "true" : "false"
        } else {
            params["database"] = database
            params["useTLS"] = useTLS ? "true" : "false"
        }
        let tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter {
            !$0.isEmpty
        }
        // S3 has no host/port/username/tunnel (the endpoint lives in params); SQLite is file-based.
        let usesServer = kind != .sqlite && kind != .s3
        let connection = Connection(
            id: existing?.id ?? UUID(),
            name: name, kind: kind,
            host: usesServer ? host : nil,
            port: usesServer ? Int(port) : nil,
            username: usesServer ? username : nil,
            params: params, tags: tags, pinned: existing?.pinned ?? false,
            createdAt: existing?.createdAt ?? Date(),
            color: color, group: group.isEmpty ? nil : group,
            tunnelBookmarkID: usesServer ? tunnelBookmarkID : nil)
        onSave(connection, buildSecret())
        dismiss()
    }

    /// Build the `ConnectionSecret` to persist, or nil to leave the stored secret unchanged. SQLite
    /// has no secret. S3 stores access key + secret key; a blank secret key on edit keeps the stored
    /// one. Server kinds store a password; a blank password on edit keeps the stored one.
    private func buildSecret() -> ConnectionSecret? {
        switch kind {
        case .sqlite:
            return nil
        case .s3:
            let existingSecret = existing.flatMap { CredentialStore.secret(for: $0.id) }
            let secretKey = s3SecretKey.isEmpty ? existingSecret?.secretKey : s3SecretKey
            // Nothing to store yet (new connection with no keys typed) → leave the Keychain untouched.
            if s3AccessKey.isEmpty && (secretKey ?? "").isEmpty && existingSecret == nil { return nil }
            return ConnectionSecret(accessKey: s3AccessKey, secretKey: secretKey)
        default:
            return password.isEmpty ? nil : ConnectionSecret(password: password)
        }
    }
}
