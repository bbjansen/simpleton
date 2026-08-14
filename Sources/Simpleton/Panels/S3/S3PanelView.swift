// Sources/Simpleton/Panels/S3/S3PanelView.swift
import AppKit
import SimpletonCore
import SimpletonS3
import SwiftUI

/// The S3 object-browser client panel: connection picker → bucket list → prefix browse with folder
/// navigation, hosted in the shared client-panel chrome. Actions: Download, Upload, Delete, Copy URL.
struct S3PanelView: View {
    @StateObject private var model: S3PanelModel
    @ObservedObject private var themeSettings = ThemeSettings.shared

    init(appSupportDir: URL) {
        _model = StateObject(wrappedValue: S3PanelModel(appSupportDir: appSupportDir))
    }

    var body: some View {
        ClientPanelScaffold(
            title: "S3",
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
                }
            )
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
            if model.selectedBucket == nil {
                bucketList
            } else {
                objectBrowser
            }
            if let status = model.status {
                ThemedDivider()
                Text(status)
                    .font(.system(size: 10)).foregroundColor(DT.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8).padding(.vertical, 4)
            }
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

    // MARK: - bucket list

    private var bucketList: some View {
        Group {
            if model.buckets.isEmpty {
                Text("No buckets in this account.")
                    .font(.system(size: 11)).foregroundColor(DT.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.buckets, id: \.name) { bucket in
                        Button {
                            Task { await model.open(bucket: bucket.name) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "cylinder").foregroundColor(DT.accentBlue)
                                Text(bucket.name).font(.system(size: 12)).foregroundColor(DT.textPrimary)
                                Spacer()
                                if let d = bucket.creationDate {
                                    Text(Self.dateFormatter.string(from: d))
                                        .font(.system(size: 10)).foregroundColor(DT.textTertiary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: - object browser

    private var objectBrowser: some View {
        VStack(spacing: 0) {
            breadcrumbBar
            ThemedDivider()
            objectTable
            if model.nextToken != nil {
                ThemedDivider()
                Button("Load more") { Task { await model.loadMore() } }
                    .font(.system(size: 11)).buttonStyle(.plain)
                    .padding(.vertical, 4)
            }
            if let err = model.errorMessage, model.isConnected {
                Text(err).font(DT.monoFont(size: 10)).foregroundColor(DT.accentRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8).padding(.vertical, 4)
            }
        }
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 4) {
            Button {
                Task { await model.goUp() }
            } label: {
                Image(systemName: "arrow.up").font(.system(size: 11))
            }
            .buttonStyle(.plain).help("Up")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    Button(model.selectedBucket ?? "") { Task { await model.navigate(toBreadcrumbIndex: nil) } }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DT.accentBlue)
                    ForEach(Array(model.breadcrumb.enumerated()), id: \.offset) { idx, part in
                        Text("/").font(.system(size: 11)).foregroundColor(DT.textTertiary)
                        Button(part) { Task { await model.navigate(toBreadcrumbIndex: idx) } }
                            .buttonStyle(.plain).font(.system(size: 11)).foregroundColor(DT.textSecondary)
                    }
                }
            }
            Spacer()
            Button {
                uploadFile()
            } label: {
                Image(systemName: "arrow.up.doc").font(.system(size: 11))
            }
            .buttonStyle(.plain).help("Upload file here").disabled(model.isBusy)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }

    private var objectTable: some View {
        Group {
            if model.rows.isEmpty {
                Text(model.isBusy ? "Loading…" : "This folder is empty.")
                    .font(.system(size: 11)).foregroundColor(DT.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.rows, id: \.key) { object in
                        objectRow(object)
                            .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    @ViewBuilder
    private func objectRow(_ object: S3Object) -> some View {
        if object.isPrefix {
            Button {
                Task { await model.navigate(intoPrefix: object.key) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill").foregroundColor(DT.accentAmber)
                    Text(object.displayName(under: model.prefix))
                        .font(.system(size: 12)).foregroundColor(DT.textPrimary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "doc").foregroundColor(DT.textSecondary)
                Text(object.displayName(under: model.prefix))
                    .font(.system(size: 12)).foregroundColor(DT.textPrimary).lineLimit(1)
                Spacer()
                Text(S3Format.humanSize(object.size))
                    .font(DT.monoFont(size: 10)).foregroundColor(DT.textTertiary)
                if let d = object.lastModified {
                    Text(Self.dateFormatter.string(from: d))
                        .font(.system(size: 10)).foregroundColor(DT.textTertiary)
                }
                objectMenu(object)
            }
            .contentShape(Rectangle())
            .contextMenu { objectActions(object) }
        }
    }

    private func objectMenu(_ object: S3Object) -> some View {
        Menu {
            objectActions(object)
        } label: {
            Image(systemName: "ellipsis.circle").font(.system(size: 11))
        }
        .menuStyle(.borderlessButton).fixedSize().menuIndicator(.hidden)
    }

    @ViewBuilder
    private func objectActions(_ object: S3Object) -> some View {
        Button("Download…") { downloadFile(object) }
        Button("Copy URL") { copyURL(object) }
        Divider()
        Button("Delete", role: .destructive) { confirmDelete(object) }
    }

    // MARK: - AppKit file dialogs & pasteboard

    private func downloadFile(_ object: S3Object) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = URL(fileURLWithPath: object.key).lastPathComponent
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            if let err = await model.download(object, to: url) { model.errorMessage = err }
        }
    }

    private func uploadFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            if let err = await model.upload(from: url) { model.errorMessage = err }
        }
    }

    private func confirmDelete(_ object: S3Object) {
        let alert = NSAlert()
        alert.messageText = "Delete \(object.displayName(under: model.prefix))?"
        alert.informativeText = "This permanently removes the object from the bucket."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            if let err = await model.delete(object) { model.errorMessage = err }
        }
    }

    private func copyURL(_ object: S3Object) {
        Task {
            guard let url = await model.presignedURL(for: object) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
            model.status = "Copied presigned URL"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}
