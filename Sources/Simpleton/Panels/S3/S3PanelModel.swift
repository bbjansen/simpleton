// Sources/Simpleton/Panels/S3/S3PanelModel.swift
import Foundation
import SimpletonCore
import SimpletonS3

@MainActor
final class S3PanelModel: ObservableObject {
    @Published var connections: [Connection] = []
    @Published var selectedID: UUID?
    @Published var buckets: [S3Bucket] = []
    @Published var selectedBucket: String?
    /// Current folder prefix within the selected bucket ("" = bucket root). Always "" or ends in "/".
    @Published var prefix: String = ""
    @Published var rows: [S3Object] = []
    @Published var nextToken: String?
    @Published var errorMessage: String?
    @Published var status: String?
    @Published var isConnecting = false
    @Published var isConnected = false
    @Published var isBusy = false
    @Published var showingEditor = false
    /// Set while a file upload is in flight; `nil` when idle. `fraction` is the determinate progress
    /// (0…1) shown in the panel, `name` is the file being uploaded.
    @Published var uploadProgress: UploadProgress?

    /// Live state for an in-flight upload, surfaced to the panel's progress indicator.
    struct UploadProgress: Equatable {
        var name: String
        var fraction: Double
    }

    /// True while an upload is running — used to disable conflicting panel actions.
    var isUploading: Bool { uploadProgress != nil }

    private let store: ConnectionStore
    private var backend: S3Backend?

    /// The connection kinds this panel manages.
    static let s3Kinds: Set<ConnectionKind> = [.s3]

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
                icon: "externaldrive.connected.to.line.below", title: "Not connected", message: errorMessage,
                actionLabel: "Connections", action: { [weak self] in self?.showingEditor = true })
        }
        return .unavailable(
            icon: "externaldrive.connected.to.line.below", title: "No connection",
            message: "Pick an S3 connection or add one.", actionLabel: "New connection",
            action: { [weak self] in self?.showingEditor = true })
    }

    /// Breadcrumb components of the current prefix (each ends without the slash), for the path bar.
    var breadcrumb: [String] {
        prefix.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    func reload() async {
        let all = await store.all()
        connections = all.filter { Self.s3Kinds.contains($0.kind) }
        if selectedID == nil { selectedID = connections.first?.id }
    }

    /// Consume a pending "open this connection" request from the Data Connections manager. Fires
    /// exactly once (guarded by the holder) whether triggered by a cold mount (`.task`) or a warm
    /// notification (`.onReceive`), and only when the pending open targets the S3 panel.
    func consumePendingOpen() async {
        guard let pending = PendingClientOpen.shared.take(for: PanelProfile.PanelID.s3) else { return }
        await reload()
        if connections.contains(where: { $0.id == pending }) {
            selectedID = pending
            await connect()
        }
    }

    func connect() async {
        // Reentrancy guard (see SQLPanelModel): `isConnecting` is set before any await so a second
        // concurrent connect() returns here instead of orphaning the first backend.
        guard !isConnecting, let connection = selectedConnection else { return }
        isConnecting = true
        defer { isConnecting = false }
        await disconnect()
        errorMessage = nil
        let secret = CredentialStore.secret(for: connection.id)
        do {
            let b = try S3BackendFactory.make(connection, secret: secret)
            do {
                try await b.connect()
            } catch {
                // Shut the AWSClient down before dropping `b`, or Soto asserts/leaks on deinit.
                await b.close()
                throw error
            }
            backend = b
            isConnected = true
            buckets = try await b.listBuckets()
            // Open the connection's default bucket if one is configured and present.
            let defaultBucket = connection.params["bucket"].flatMap { $0.isEmpty ? nil : $0 }
            if let db = defaultBucket, buckets.contains(where: { $0.name == db }) {
                await open(bucket: db)
            } else {
                selectedBucket = nil
            }
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    func disconnect() async {
        if let backend { await backend.close() }
        backend = nil
        isConnected = false
        buckets = []
        selectedBucket = nil
        prefix = ""
        rows = []
        nextToken = nil
        status = nil
    }

    /// Connect to whatever is currently selected (or disconnect if the selection was cleared).
    func connectSelected() async {
        if selectedID == nil {
            await disconnect()
        } else {
            await connect()
        }
    }

    func open(bucket: String) async {
        selectedBucket = bucket
        prefix = ""
        await listCurrent(reset: true)
    }

    func navigate(intoPrefix newPrefix: String) async {
        prefix = newPrefix
        await listCurrent(reset: true)
    }

    /// Go up one folder level. At the bucket root this returns to the bucket list.
    func goUp() async {
        guard !prefix.isEmpty else {
            selectedBucket = nil
            rows = []
            nextToken = nil
            return
        }
        let parts = prefix.split(separator: "/", omittingEmptySubsequences: true).dropLast()
        prefix = parts.isEmpty ? "" : parts.joined(separator: "/") + "/"
        await listCurrent(reset: true)
    }

    /// Jump to a breadcrumb level (index in `breadcrumb`); a nil index means the bucket root.
    func navigate(toBreadcrumbIndex index: Int?) async {
        guard let index else {
            prefix = ""
            await listCurrent(reset: true)
            return
        }
        let parts = prefix.split(separator: "/", omittingEmptySubsequences: true).prefix(index + 1)
        prefix = parts.joined(separator: "/") + "/"
        await listCurrent(reset: true)
    }

    func loadMore() async {
        guard nextToken != nil else { return }
        await listCurrent(reset: false)
    }

    private func listCurrent(reset: Bool) async {
        guard let backend, let bucket = selectedBucket else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            let page = try await backend.list(
                bucket: bucket, prefix: prefix, continuationToken: reset ? nil : nextToken)
            let folders = page.commonPrefixes.map { S3Object(key: $0, size: 0, isPrefix: true) }
            let newRows = folders + page.objects
            rows = reset ? newRows : rows + newRows
            nextToken = page.nextToken
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    func refreshCurrent() async {
        if selectedBucket == nil {
            guard let backend else { return }
            buckets = (try? await backend.listBuckets()) ?? buckets
        } else {
            await listCurrent(reset: true)
        }
    }

    // MARK: - object actions

    /// Download `object` to `destination`; returns an error message on failure, nil on success.
    func download(_ object: S3Object, to destination: URL) async -> String? {
        guard let backend, let bucket = selectedBucket else { return "Not connected." }
        isBusy = true
        defer { isBusy = false }
        do {
            let data = try await backend.download(bucket: bucket, key: object.key)
            try data.write(to: destination)
            status = "Downloaded \(object.displayName(under: prefix))"
            return nil
        } catch {
            return Self.describe(error)
        }
    }

    /// Upload a local file into the current folder under its filename. Streams the file by URL (so
    /// multi-GB files never load fully into memory) and drives a determinate progress indicator; large
    /// files go through multipart upload in the backend. Returns an error message on failure, nil on
    /// success.
    func upload(from source: URL) async -> String? {
        guard let backend, let bucket = selectedBucket else { return "Not connected." }
        guard !isUploading else { return "An upload is already in progress." }
        isBusy = true
        uploadProgress = UploadProgress(name: source.lastPathComponent, fraction: 0)
        defer {
            isBusy = false
            uploadProgress = nil
        }
        let key = prefix + source.lastPathComponent
        do {
            // The progress callback is `@Sendable` and fires off the main actor (Soto's per-part hook).
            // Forward each fraction to the main-actor updater without capturing `self` in the closure.
            let update: @Sendable (Double) async -> Void = { [applyProgress] fraction in
                await applyProgress(fraction)
            }
            try await backend.upload(bucket: bucket, key: key, fileURL: source) { fraction in
                await update(fraction)
            }
            status = "Uploaded \(source.lastPathComponent)"
            await listCurrent(reset: true)
            return nil
        } catch {
            return Self.describe(error)
        }
    }

    /// Publish an upload progress fraction (0…1). Called on the main actor from the upload task's
    /// forwarding closure so the determinate indicator updates as each part completes.
    @MainActor
    private func applyProgress(_ fraction: Double) {
        guard var current = uploadProgress else { return }
        current.fraction = min(max(fraction, 0), 1)
        uploadProgress = current
    }

    func delete(_ object: S3Object) async -> String? {
        guard let backend, let bucket = selectedBucket else { return "Not connected." }
        isBusy = true
        defer { isBusy = false }
        do {
            try await backend.delete(bucket: bucket, key: object.key)
            status = "Deleted \(object.displayName(under: prefix))"
            await listCurrent(reset: true)
            return nil
        } catch {
            return Self.describe(error)
        }
    }

    /// A presigned GET URL for `object`, valid one hour. Returns nil (and sets `errorMessage`) on
    /// failure.
    func presignedURL(for object: S3Object) async -> URL? {
        guard let backend, let bucket = selectedBucket else { return nil }
        do {
            return try await backend.presignGetURL(bucket: bucket, key: object.key, expires: 3600)
        } catch {
            errorMessage = Self.describe(error)
            return nil
        }
    }

    func saveConnection(_ connection: Connection, secret: ConnectionSecret?) async {
        try? await store.add(connection)
        if let secret { CredentialStore.store(secret, for: connection.id) }
        await reload()
        selectedID = connection.id
        await connect()
    }

    private static func describe(_ error: Error) -> String {
        if let e = error as? S3Error {
            switch e {
            case .auth(let m): return "Authentication failed: \(m)"
            case .notFound(let m): return "Not found: \(m)"
            case .connectionFailed(let m): return m
            case .unsupported(let m): return m
            }
        }
        return "\(error)"
    }
}
