// Sources/Simpleton/Panels/AMQP/AMQPPanelModel.swift
import Foundation
import SimpletonAMQP
import SimpletonCore

/// Which management table the panel is currently showing.
enum AMQPTab: String, CaseIterable, Identifiable {
    case queues = "Queues"
    case exchanges = "Exchanges"
    case connections = "Connections"
    case channels = "Channels"
    var id: String { rawValue }
}

@MainActor
final class AMQPPanelModel: ObservableObject {
    @Published var connections: [Connection] = []
    @Published var selectedID: UUID?
    @Published var errorMessage: String?
    @Published var isConnecting = false
    @Published var isConnected = false
    @Published var showingEditor = false

    @Published var tab: AMQPTab = .queues
    @Published var overview: Overview?
    @Published var queues: [QueueInfo] = []
    @Published var exchanges: [ExchangeInfo] = []
    @Published var brokerConnections: [ConnectionInfo] = []
    @Published var channels: [ChannelInfo] = []

    /// Sheet state for a queue's peeked messages.
    @Published var messagePreview: [MessagePreview]?
    @Published var messagePreviewQueue: String?
    /// Sheet state for publishing.
    @Published var publishTarget: QueueInfo?
    /// Confirmation state for purging.
    @Published var purgeTarget: QueueInfo?

    private let store: ConnectionStore
    private var backend: AMQPManagementBackend?

    /// The connection kinds this panel manages.
    static let amqpKinds: Set<ConnectionKind> = [.amqp]

    init(appSupportDir: URL) {
        self.store = ConnectionStore(directory: appSupportDir)
    }

    var selectedConnection: Connection? {
        guard let selectedID else { return nil }
        return connections.first { $0.id == selectedID }
    }

    /// The vhost of the selected connection (default `/`).
    var vhost: String { selectedConnection?.params["vhost"] ?? "/" }

    var availability: ClientAvailability {
        if isConnecting { return .loading }
        if isConnected { return .ready }
        if let errorMessage {
            return .unavailable(
                icon: "arrow.left.arrow.right", title: "Not connected", message: errorMessage,
                actionLabel: "Connections", action: { [weak self] in self?.showingEditor = true })
        }
        return .unavailable(
            icon: "arrow.left.arrow.right", title: "No connection",
            message: "Pick a RabbitMQ connection or add one.", actionLabel: "New connection",
            action: { [weak self] in self?.showingEditor = true })
    }

    func reload() async {
        let all = await store.all()
        connections = all.filter { Self.amqpKinds.contains($0.kind) }
        if selectedID == nil { selectedID = connections.first?.id }
    }

    /// Consume a pending "open this connection" request from the Data Connections manager. Guarded by
    /// the holder so it fires exactly once whether triggered by a cold mount (`.task`) or a warm
    /// notification (`.onReceive`), and only when the pending open targets the AMQP panel.
    func consumePendingOpen() async {
        guard let pending = PendingClientOpen.shared.take(for: PanelProfile.PanelID.amqp) else { return }
        await reload()
        if connections.contains(where: { $0.id == pending }) {
            selectedID = pending
            await connect()
        }
    }

    func connect() async {
        // Reentrancy guard: `isConnecting` is set synchronously (before any await) so a second
        // concurrent connect() returns here instead of racing and orphaning the first backend.
        guard !isConnecting, let connection = selectedConnection else { return }
        isConnecting = true
        defer { isConnecting = false }
        await disconnect()
        errorMessage = nil
        let secret = CredentialStore.secret(for: connection.id)
        do {
            let b = try AMQPBackendFactory.make(connection, secret: secret)
            // overview() doubles as a connectivity + auth probe before we call it "connected".
            overview = try await b.overview()
            backend = b
            isConnected = true
            await refresh()
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    func disconnect() async {
        backend = nil
        isConnected = false
        overview = nil
        queues = []
        exchanges = []
        brokerConnections = []
        channels = []
    }

    /// Reload every table (called by connect, the scaffold's manual refresh, and auto-refresh).
    func refresh() async {
        guard let backend else { return }
        errorMessage = nil
        do {
            overview = try await backend.overview()
            queues = try await backend.queues(vhost: vhost)
            exchanges = try await backend.exchanges(vhost: vhost)
            brokerConnections = try await backend.connections()
            channels = try await backend.channels()
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    // MARK: - Queue row actions

    func getMessages(for queue: QueueInfo, count: Int = 10) async {
        guard let backend else { return }
        do {
            let messages = try await backend.getMessages(vhost: queue.vhost, queue: queue.name, count: count)
            messagePreview = messages
            messagePreviewQueue = queue.name
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    func publish(exchange: String, routingKey: String, payload: String) async {
        guard let backend else { return }
        do {
            _ = try await backend.publish(
                vhost: vhost, exchange: exchange, routingKey: routingKey, payload: payload)
            publishTarget = nil
            await refresh()
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    func purge(_ queue: QueueInfo) async {
        guard let backend else { return }
        do {
            try await backend.purge(vhost: queue.vhost, queue: queue.name)
            purgeTarget = nil
            await refresh()
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    func saveConnection(_ connection: Connection, secret: ConnectionSecret?) async {
        try? await store.add(connection)
        if let secret { CredentialStore.store(secret, for: connection.id) }
        await reload()
        selectedID = connection.id
        await connect()
    }

    /// Connect to whatever is currently selected (or disconnect if the selection was cleared).
    func connectSelected() async {
        if selectedID == nil {
            await disconnect()
        } else {
            await connect()
        }
    }

    private static func describe(_ error: Error) -> String {
        if let e = error as? AMQPError { return e.message }
        return "\(error)"
    }
}
