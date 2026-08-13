// Sources/Simpleton/Panels/SFTP/SFTPPanelView.swift
import AppKit
import SimpletonCore
import SimpletonSFTP
import SwiftUI

/// The SFTP client panel: a remote file browser hosted in the shared client-panel chrome. Connection
/// picker + breadcrumb + directory listing, with download / upload / mkdir / rename / delete actions
/// backed by real Citadel calls. Mirrors `SQLPanelView`.
struct SFTPPanelView: View {
    @StateObject private var model: SFTPPanelModel
    @ObservedObject private var themeSettings = ThemeSettings.shared

    @State private var selection: FileEntry.ID?
    @State private var showingNewFolder = false
    @State private var newFolderName = ""
    @State private var renaming: FileEntry?
    @State private var renameText = ""
    @State private var deleting: FileEntry?

    init(appSupportDir: URL) {
        _model = StateObject(wrappedValue: SFTPPanelModel(appSupportDir: appSupportDir))
    }

    var body: some View {
        ClientPanelScaffold(
            title: "SFTP",
            availability: model.availability,
            autoRefresh: nil,
            onRefresh: { await model.reload() }
        ) {
            content
        }
        .sheet(isPresented: $model.showingEditor) {
            DataConnectionEditor(
                bookmarks: [], existingGroups: [], existing: nil,
                onSave: { connection, secret in
                    Task { await model.saveConnection(connection, secret: secret) }
                })
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
            if model.isConnected {
                toolbar
                ThemedDivider()
                breadcrumbBar
                ThemedDivider()
                listing
                if let err = model.errorMessage {
                    ThemedDivider()
                    Text(err).font(DT.monoFont(size: 10)).foregroundColor(DT.accentRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                }
            }
        }
        .confirmationDialog(
            "Delete \(deleting?.name ?? "")?", isPresented: deleteBinding, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let entry = deleting { Task { await model.delete(entry) } }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text(deleting?.isDirectory == true ? "This removes the directory (must be empty)." : "")
        }
        .sheet(isPresented: $showingNewFolder) { newFolderSheet }
        .sheet(item: $renaming) { entry in renameSheet(entry) }
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
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                Task { await model.goUp() }
            } label: {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.plain).help("Parent directory").disabled(model.currentPath == "/")
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain).help("Refresh")
            Divider().frame(height: 14)
            Button {
                downloadSelected()
            } label: {
                Image(systemName: "arrow.down.circle")
            }
            .buttonStyle(.plain).help("Download").disabled(!selectedIsFile)
            Button {
                uploadFile()
            } label: {
                Image(systemName: "arrow.up.circle")
            }
            .buttonStyle(.plain).help("Upload")
            Button {
                newFolderName = ""
                showingNewFolder = true
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(.plain).help("New folder")
            Button {
                if let entry = selectedEntry {
                    renameText = entry.name
                    renaming = entry
                }
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain).help("Rename").disabled(selectedEntry == nil)
            Button {
                deleting = selectedEntry
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain).help("Delete").disabled(selectedEntry == nil)
            Spacer()
            if model.isBusy { ProgressView().controlSize(.small) }
        }
        .foregroundColor(DT.textSecondary)
        .padding(.horizontal, 8).padding(.vertical, 6)
    }

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(model.breadcrumb.enumerated()), id: \.offset) { index, crumb in
                    if index > 0 {
                        Image(systemName: "chevron.right").font(.system(size: 8))
                            .foregroundColor(DT.textTertiary)
                    }
                    Button(crumb.label) { Task { await model.navigate(to: crumb.path) } }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(crumb.path == model.currentPath ? DT.textPrimary : DT.textSecondary)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
        }
    }

    private var listing: some View {
        Table(model.entries, selection: $selection) {
            TableColumn("Name") { entry in
                HStack(spacing: 6) {
                    Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                        .foregroundColor(entry.isDirectory ? DT.accentBlue : DT.textSecondary)
                    Text(entry.name).foregroundColor(DT.textPrimary)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { Task { await model.open(entry) } }
            }
            TableColumn("Size") { entry in
                Text(entry.isDirectory ? "—" : Self.formatSize(entry.size))
                    .font(DT.monoFont(size: 11)).foregroundColor(DT.textSecondary)
            }
            .width(72)
            TableColumn("Modified") { entry in
                Text(entry.modified.map(Self.formatDate) ?? "—")
                    .font(.system(size: 11)).foregroundColor(DT.textTertiary)
            }
            .width(130)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - sheets

    private var newFolderSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Folder").font(.headline).foregroundColor(DT.textPrimary)
            TextField("Folder name", text: $newFolderName).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { showingNewFolder = false }
                Button("Create") {
                    let name = newFolderName
                    showingNewFolder = false
                    Task { await model.makeDirectory(named: name) }
                }
                .keyboardShortcut(.defaultAction).disabled(newFolderName.isEmpty)
            }
        }
        .padding(16).frame(width: 320).background(DT.base)
    }

    private func renameSheet(_ entry: FileEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename").font(.headline).foregroundColor(DT.textPrimary)
            TextField("New name", text: $renameText).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { renaming = nil }
                Button("Rename") {
                    let name = renameText
                    renaming = nil
                    Task { await model.rename(entry, to: name) }
                }
                .keyboardShortcut(.defaultAction).disabled(renameText.isEmpty)
            }
        }
        .padding(16).frame(width: 320).background(DT.base)
    }

    // MARK: - selection helpers

    private var selectedEntry: FileEntry? {
        guard let selection else { return nil }
        return model.entries.first { $0.id == selection }
    }

    private var selectedIsFile: Bool {
        selectedEntry.map { !$0.isDirectory } ?? false
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    // MARK: - file panels

    private func downloadSelected() {
        guard let entry = selectedEntry, !entry.isDirectory else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = entry.name
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            if let data = await model.download(entry) {
                try? data.write(to: url)
            }
        }
    }

    private func uploadFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.upload(localURL: url) }
    }

    // MARK: - formatting

    private static func formatSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }
}
