// Sources/Simpleton/Panels/SQL/SQLConnectionEditor.swift
import SimpletonCore
import SwiftUI

/// A sheet to add a SQL connection (SQLite path, or server host/port/user/password/database).
struct SQLConnectionEditor: View {
    @Environment(\.dismiss) private var dismiss
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

    private let kinds: [ConnectionKind] = [.postgres, .mysql, .sqlite]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New SQL Connection").font(.headline).foregroundColor(DT.textPrimary)
            Picker("Type", selection: $kind) {
                ForEach(kinds, id: \.self) { Text($0.displayName).tag($0) }
            }
            .onChange(of: kind) {
                if port.isEmpty, let p = kind.defaultPort { port = String(p) }
            }
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
                SecureField("Password", text: $password).textFieldStyle(.roundedBorder)
                Toggle("Use TLS", isOn: $useTLS)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(name.isEmpty)
            }
        }
        .padding(16).frame(width: 380)
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
        let connection = Connection(
            name: name, kind: kind,
            host: kind == .sqlite ? nil : host,
            port: kind == .sqlite ? nil : Int(port),
            username: kind == .sqlite ? nil : username,
            params: params)
        let secret = (kind == .sqlite || password.isEmpty) ? nil : ConnectionSecret(password: password)
        onSave(connection, secret)
        dismiss()
    }
}
