// Sources/Simpleton/Panels/SFTP/SFTPPanelModel.swift
import Foundation
import SimpletonCore
import SimpletonSFTP

/// GUI-client model for the SFTP file browser. Mirrors `SQLPanelModel`: filters connections by the
/// SFTP kinds, connects via `SFTPBackendFactory`, and drives the directory listing / file operations.
@MainActor
final class SFTPPanelModel: ObservableObject {
    @Published var connections: [Connection] = []
    @Published var selectedID: UUID?
    @Published var entries: [FileEntry] = []
    @Published var currentPath: String = "/"
    @Published var errorMessage: String?
    @Published var isConnecting = false
    @Published var isConnected = false
    @Published var isBusy = false
    @Published var showingEditor = false

    private let store: ConnectionStore
    private var backend: SFTPBackend?

    /// The connection kinds this panel manages. `.ftp` is included so a classic-FTP-labelled
    /// connection still opens the SFTP browser (classic FTP itself is deprecated / not implemented).
    static let sftpKinds: Set<ConnectionKind> = [.sftp, .ftp]

    init(appSupportDir: URL) {
        self.store = ConnectionStore(directory: appSupportDir)
    }

    var selectedConnection: Connection? {
        guard let selectedID else { return nil }
        return connections.first { $0.id == selectedID }
    }

    var availability: ClientAvailability {
        if isConnecting { return .loading }
        if isConnected { return .ready }
        if let errorMessage {
            return .unavailable(
                icon: "folder.badge.gearshape", title: "Not connected", message: errorMessage,
                actionLabel: "Connections", action: { [weak self] in self?.showingEditor = true })
        }
        return .unavailable(
            icon: "folder.badge.gearshape", title: "No connection",
            message: "Pick an SFTP connection or add one.", actionLabel: "New connection",
            action: { [weak self] in self?.showingEditor = true })
    }

    /// Path components for the breadcrumb, always rooted at "/".
    var breadcrumb: [(label: String, path: String)] {
        var crumbs: [(String, String)] = [("/", "/")]
        var accumulated = ""
        for part in currentPath.split(separator: "/") {
            accumulated += "/\(part)"
            crumbs.append((String(part), accumulated))
        }
        return crumbs
    }

    func reload() async {
        let all = await store.all()
        connections = all.filter { Self.sftpKinds.contains($0.kind) }
        if selectedID == nil { selectedID = connections.first?.id }
    }

    /// Consume a pending "open this connection" request from the Data Connections manager. Fires
    /// exactly once (guarded by the holder) whether from a cold mount (`.task`) or warm notification
    /// (`.onReceive`), and only when the pending open targets the SFTP panel.
    func consumePendingOpen() async {
        guard let pending = PendingClientOpen.shared.take(for: PanelProfile.PanelID.sftp) else { return }
        await reload()
        if connections.contains(where: { $0.id == pending }) {
            selectedID = pending
            await connect()
        }
    }

    func connect() async {
        // Reentrancy guard set synchronously (before any await) so a double-click / reveal-remount
        // re-firing `.task` returns here instead of racing and orphaning the first backend.
        guard !isConnecting, let connection = selectedConnection else { return }
        isConnecting = true
        defer { isConnecting = false }
        await disconnect()
        errorMessage = nil
        let secret = CredentialStore.secret(for: connection.id)
        do {
            let b = try SFTPBackendFactory.make(connection, secret: secret)
            do {
                try await b.connect()
            } catch {
                // Close any half-open SSH channel before dropping `b` (openSFTP can fail after the
                // SSH client connected), instead of leaking it.
                await b.close()
                throw error
            }
            backend = b
            isConnected = true
            // Start at the login home directory.
            let home = (try? await b.realPath(".")) ?? "/"
            await navigate(to: home)
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    func disconnect() async {
        if let backend { await backend.close() }
        backend = nil
        isConnected = false
        entries = []
    }

    /// Connect to whatever is currently selected (or disconnect if the selection was cleared).
    func connectSelected() async {
        if selectedID == nil {
            await disconnect()
        } else {
            await connect()
        }
    }

    func navigate(to path: String) async {
        guard let backend else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            let listed = try await backend.list(path: path)
            currentPath = path
            entries = listed
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    func open(_ entry: FileEntry) async {
        guard entry.isDirectory else { return }
        await navigate(to: entry.path)
    }

    func goUp() async {
        guard currentPath != "/" else { return }
        let parent = (currentPath as NSString).deletingLastPathComponent
        await navigate(to: parent.isEmpty ? "/" : parent)
    }

    func refresh() async {
        if isConnected { await navigate(to: currentPath) }
    }

    /// Read a remote file's bytes for saving locally. Returns nil (and sets `errorMessage`) on failure.
    func download(_ entry: FileEntry) async -> Data? {
        guard let backend, !entry.isDirectory else { return nil }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            return try await backend.download(path: entry.path)
        } catch {
            errorMessage = Self.describe(error)
            return nil
        }
    }

    /// Upload a local file into the current remote directory under its own filename.
    func upload(localURL: URL) async {
        guard let backend else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            let data = try Data(contentsOf: localURL)
            let remote = joinPath(currentPath, localURL.lastPathComponent)
            try await backend.upload(path: remote, data: data)
            await navigate(to: currentPath)
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    func makeDirectory(named name: String) async {
        guard let backend, !name.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            try await backend.makeDirectory(path: joinPath(currentPath, name))
            await navigate(to: currentPath)
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    func rename(_ entry: FileEntry, to newName: String) async {
        guard let backend, !newName.isEmpty, newName != entry.name else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            let dest = joinPath(currentPath, newName)
            try await backend.rename(from: entry.path, to: dest)
            await navigate(to: currentPath)
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    func delete(_ entry: FileEntry) async {
        guard let backend else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            if entry.isDirectory {
                try await backend.removeDirectory(path: entry.path)
            } else {
                try await backend.remove(path: entry.path)
            }
            await navigate(to: currentPath)
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    func saveConnection(_ connection: Connection, secret: ConnectionSecret?) async {
        try? await store.add(connection)
        if let secret { CredentialStore.store(secret, for: connection.id) }
        await reload()
        selectedID = connection.id
        await connect()  // a freshly added connection connects + browses immediately
    }

    private func joinPath(_ dir: String, _ name: String) -> String {
        dir == "/" ? "/\(name)" : "\(dir)/\(name)"
    }

    private static func describe(_ error: Error) -> String {
        if let e = error as? SFTPError { return e.message }
        return "\(error)"
    }
}
