// Sources/Simpleton/Views/ConnectionFormView.swift
import SwiftUI
import SimpletonCore

struct ConnectionFormView: View {
    @State var bookmark: Bookmark
    let isNew: Bool
    let onSave: (Bookmark) -> Void
    let onCancel: () -> Void

    @State private var password = ""
    @State private var validationError: String?

    // Jump hosts need stable identity so adding/removing rows in a single run-loop
    // turn can't crash an index-keyed ForEach. We keep an id-tagged mirror of
    // bookmark.jumpHosts and sync it back on every mutation.
    @State private var jumpHostRows: [JumpHostRow] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: isNew ? "plus.circle.fill" : "pencil.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isNew ? "New Connection" : "Edit Connection")
                        .font(.system(size: 16, weight: .semibold))
                    Text(isNew ? "Configure a new SSH connection" : "Modify connection settings")
                        .font(.system(size: 11))
                        .foregroundColor(DT.textTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Rectangle()
                .fill(DT.border.opacity(0.5))
                .frame(height: 0.5)

            Form {
                Section {
                    TextField("Name", text: $bookmark.name)
                    TextField("Host", text: $bookmark.host)
                    Stepper("Port: \(bookmark.port)", value: $bookmark.port, in: 1...65535)
                    TextField("User", text: Binding(
                        get: { bookmark.user ?? "" },
                        set: { bookmark.user = $0.isEmpty ? nil : $0 }
                    ))
                } header: {
                    FormSectionHeader(title: "Connection")
                }

                Section {
                    Picker("Method", selection: Binding(
                        get: { authMethodTag },
                        set: { setAuthMethod($0) }
                    )) {
                        Text("SSH Agent").tag("agent")
                        Text("Key File").tag("key")
                        Text("Password").tag("password")
                        Text("None").tag("none")
                    }

                    if case .key(let file) = bookmark.auth {
                        TextField("Identity file", text: Binding(
                            get: { file },
                            set: { bookmark.auth = .key(identityFile: $0) }
                        ))
                    }

                    if case .password = bookmark.auth {
                        SecureField("Password (stored in Keychain)", text: $password)
                    }
                } header: {
                    FormSectionHeader(title: "Authentication")
                }

                Section {
                    ForEach(Array(jumpHostRows.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 8) {
                            // Numbered circle showing chain order
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(DT.textTertiary)
                                .frame(width: 20, height: 20)
                                .background(DT.elevated)
                                .clipShape(Circle())

                            TextField("Jump host \(index + 1)", text: Binding(
                                get: { row.value },
                                set: { newValue in
                                    guard let idx = jumpHostRows.firstIndex(where: { $0.id == row.id }) else { return }
                                    jumpHostRows[idx].value = newValue
                                    syncJumpHosts()
                                }
                            ))
                            Button(action: { removeJumpHost(id: row.id) }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button(action: {
                        jumpHostRows.append(JumpHostRow(value: ""))
                        syncJumpHosts()
                    }) {
                        Label("Add jump host", systemImage: "plus")
                            .foregroundColor(.accentColor)
                    }
                } header: {
                    FormSectionHeader(title: "Jump Hosts")
                }

                Section {
                    ForEach(Array(bookmark.portForwards.enumerated()), id: \.offset) { index, pf in
                        HStack {
                            Text(pf.direction == .local ? "L" : "R")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(pf.direction == .local ? DT.accentBlue : .orange)
                                .frame(width: 16)
                            Text("\(pf.localPort):\(pf.remoteHost):\(pf.remotePort)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.primary)
                            Spacer()
                            Button(action: { bookmark.portForwards.remove(at: index) }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    FormSectionHeader(title: "Port Forwards")
                }

                Section {
                    TextField("Tags (comma-separated)", text: Binding(
                        get: { bookmark.tags.joined(separator: ", ") },
                        set: { bookmark.tags = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                    ))
                    Toggle("Pinned", isOn: $bookmark.pinned)
                    TextField("Notes", text: $bookmark.notes, axis: .vertical)
                        .lineLimit(3)
                } header: {
                    FormSectionHeader(title: "Organization")
                }

                if let error = validationError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(DT.accentRed)
                            .font(.system(size: 11))
                        Text(error)
                            .foregroundColor(DT.accentRed)
                            .font(.system(size: 11))
                    }
                }
            }
            .formStyle(.grouped)

            Rectangle()
                .fill(DT.border.opacity(0.5))
                .frame(height: 0.5)

            // Footer buttons — Save filled, Cancel ghost
            HStack(spacing: 12) {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered)
                Spacer()
                Button(isNew ? "Create" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(bookmark.name.isEmpty || bookmark.host.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 480, height: 600)
        .background(DT.base)
        .onAppear {
            jumpHostRows = bookmark.jumpHosts.map { JumpHostRow(value: $0) }
        }
    }

    private func syncJumpHosts() {
        bookmark.jumpHosts = jumpHostRows.map(\.value)
    }

    private func removeJumpHost(id: UUID) {
        jumpHostRows.removeAll { $0.id == id }
        syncJumpHosts()
    }

    private var authMethodTag: String {
        switch bookmark.auth {
        case .key: return "key"
        case .password: return "password"
        case .agent: return "agent"
        case .none: return "none"
        }
    }

    private func setAuthMethod(_ tag: String) {
        switch tag {
        case "key": bookmark.auth = .key(identityFile: "~/.ssh/id_ed25519")
        case "password": bookmark.auth = .password
        case "agent": bookmark.auth = .agent
        case "none": bookmark.auth = .none
        default: break
        }
    }

    private func save() {
        guard FieldValidator.isValidHostname(bookmark.host) else {
            validationError = "Invalid hostname"
            return
        }
        if let user = bookmark.user, !FieldValidator.isValidUsername(user) {
            validationError = "Invalid username"
            return
        }

        // Store password in Keychain if provided
        if case .password = bookmark.auth, !password.isEmpty {
            _ = KeychainManager.storePassword(password, for: bookmark.id)
        }

        bookmark.jumpHosts = bookmark.jumpHosts.filter { !$0.isEmpty }
        validationError = nil
        onSave(bookmark)
    }
}

// MARK: - Jump Host Row

/// Stable-identity wrapper for a jump-host string so an index-keyed ForEach can't
/// bind to an out-of-range index when rows are added/removed in one run-loop turn.
private struct JumpHostRow: Identifiable {
    let id = UUID()
    var value: String
}

// MARK: - Form Section Header

struct FormSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.2)
            .foregroundColor(DT.textTertiary)
    }
}
