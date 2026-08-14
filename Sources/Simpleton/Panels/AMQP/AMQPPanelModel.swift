// Sources/Simpleton/Panels/AMQP/AMQPPanelModel.swift
import Foundation
import SimpletonAMQP
import SimpletonCore

/// Which management table the panel is currently showing.
enum AMQPTab: String, CaseIterable, Identifiable {
    case queues = "Queues"
    case exchanges = "Exchanges"
    case bindings = "Bindings"
    case graph = "Graph"
    case policies = "Policies"
    case connections = "Connections"
    case channels = "Channels"
    case nodes = "Nodes"
    var id: String { rawValue }
}

/// Input for the New Queue sheet, carrying the optional TTL / dead-letter policy args. Kept in the
/// model so the sheet stays a pure form and the model owns the argument-map construction.
struct NewQueueSpec {
    var name = ""
    var durable = true
    var autoDelete = false
    /// Message TTL in milliseconds (`x-message-ttl`); blank = unset.
    var messageTTL = ""
    /// Dead-letter exchange (`x-dead-letter-exchange`); blank = unset.
    var deadLetterExchange = ""
    /// Dead-letter routing key (`x-dead-letter-routing-key`); blank = unset.
    var deadLetterRoutingKey = ""

    /// Build the RabbitMQ `arguments` map from the filled-in policy fields. Empty fields are omitted;
    /// a non-numeric TTL is dropped rather than sent as a bad value.
    var arguments: [String: QueueArgument] {
        var args: [String: QueueArgument] = [:]
        let ttl = messageTTL.trimmingCharacters(in: .whitespaces)
        if !ttl.isEmpty, let ms = Int(ttl) { args["x-message-ttl"] = .int(ms) }
        let dlx = deadLetterExchange.trimmingCharacters(in: .whitespaces)
        if !dlx.isEmpty { args["x-dead-letter-exchange"] = .string(dlx) }
        let dlrk = deadLetterRoutingKey.trimmingCharacters(in: .whitespaces)
        if !dlrk.isEmpty { args["x-dead-letter-routing-key"] = .string(dlrk) }
        return args
    }
}

/// Input for the New Exchange sheet.
struct NewExchangeSpec {
    var name = ""
    var type = "direct"
    var durable = true
    var autoDelete = false

    static let types = ["direct", "topic", "fanout", "headers"]
}

/// Input for the New Binding sheet (queue ← exchange).
struct NewBindingSpec {
    var source = ""
    var destination = ""
    var routingKey = ""
}

/// Input for the New Policy sheet. A policy applies its `definition` (TTL / DLX / max-length) to
/// every object matching `pattern` in `applyTo` — the correct way to set TTL/DLX on *existing*
/// queues (queue arguments are immutable after declaration). Empty / non-numeric definition rows are
/// dropped exactly like the New Queue sheet does, so a blank field never sends a bad value.
struct NewPolicySpec {
    var name = ""
    /// Regex matched against object names (`.*` = everything, `^orders\\.` = a prefix, …).
    var pattern = ".*"
    /// `queues`, `exchanges`, or `all`.
    var applyTo = "queues"
    var priority = "0"
    /// Message TTL in milliseconds (`message-ttl`); blank = unset.
    var messageTTL = ""
    /// Dead-letter exchange (`dead-letter-exchange`); blank = unset.
    var deadLetterExchange = ""
    /// Dead-letter routing key (`dead-letter-routing-key`); blank = unset.
    var deadLetterRoutingKey = ""
    /// Max queue length (`max-length`); blank = unset.
    var maxLength = ""

    static let applyToOptions = ["queues", "exchanges", "all"]

    /// The parsed priority (defaults to 0 if blank / non-numeric).
    var priorityValue: Int {
        Int(priority.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    /// Build the RabbitMQ policy `definition` map from the filled-in fields. Empty fields are omitted;
    /// a non-numeric TTL / max-length is dropped rather than sent as a bad value.
    var definition: [String: PolicyValue] {
        var def: [String: PolicyValue] = [:]
        let ttl = messageTTL.trimmingCharacters(in: .whitespaces)
        if !ttl.isEmpty, let ms = Int(ttl) { def["message-ttl"] = .int(ms) }
        let dlx = deadLetterExchange.trimmingCharacters(in: .whitespaces)
        if !dlx.isEmpty { def["dead-letter-exchange"] = .string(dlx) }
        let dlrk = deadLetterRoutingKey.trimmingCharacters(in: .whitespaces)
        if !dlrk.isEmpty { def["dead-letter-routing-key"] = .string(dlrk) }
        let maxLen = maxLength.trimmingCharacters(in: .whitespaces)
        if !maxLen.isEmpty, let n = Int(maxLen) { def["max-length"] = .int(n) }
        return def
    }
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
    @Published var bindings: [BindingInfo] = []
    @Published var brokerConnections: [ConnectionInfo] = []
    @Published var channels: [ChannelInfo] = []
    @Published var nodes: [NodeInfo] = []
    @Published var policies: [PolicyInfo] = []
    /// Rolling per-node metrics history (memory / fd), sampled on every refresh. In-memory only —
    /// resets when the panel closes; that is intentional for a live monitor (see NodeMetricsHistory).
    @Published var metricsHistory = NodeMetricsHistory(capacity: 60)

    /// Sheet state for a queue's peeked messages.
    @Published var messagePreview: [MessagePreview]?
    @Published var messagePreviewQueue: String?
    /// Sheet state for publishing.
    @Published var publishTarget: QueueInfo?
    /// Confirmation state for purging.
    @Published var purgeTarget: QueueInfo?
    /// Sheet presentation for the New Queue / New Exchange / New Binding / New Policy forms.
    @Published var showingNewQueue = false
    @Published var showingNewExchange = false
    @Published var showingNewBinding = false
    @Published var showingNewPolicy = false
    /// Confirmation state for deleting a queue / an exchange / a policy.
    @Published var deleteQueueTarget: QueueInfo?
    @Published var deleteExchangeTarget: ExchangeInfo?
    @Published var deletePolicyTarget: PolicyInfo?

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
        bindings = []
        brokerConnections = []
        channels = []
        nodes = []
        policies = []
        metricsHistory = NodeMetricsHistory(capacity: 60)
    }

    /// Reload every table (called by connect, the scaffold's manual refresh, and auto-refresh).
    func refresh() async {
        guard let backend else { return }
        errorMessage = nil
        do {
            overview = try await backend.overview()
            queues = try await backend.queues(vhost: vhost)
            exchanges = try await backend.exchanges(vhost: vhost)
            bindings = try await backend.bindings(vhost: vhost)
            policies = try await backend.policies(vhost: vhost)
            brokerConnections = try await backend.connections()
            channels = try await backend.channels()
            nodes = try await backend.nodes()
            recordMetrics(from: nodes)
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// Append one metrics sample per node to the rolling history. Called after every successful
    /// refresh so the Nodes charts accumulate a live memory / fd time series.
    private func recordMetrics(from nodes: [NodeInfo]) {
        for node in nodes {
            metricsHistory.record(node: node.name, memUsed: node.memUsed, fdUsed: node.fdUsed)
        }
    }

    /// The deterministic bindings-graph layout for the Graph tab, built from the current
    /// exchanges / queues / bindings. Recomputed on demand (cheap, pure) so it always reflects the
    /// latest refresh.
    var graphLayout: AMQPBindingsGraph.Layout {
        AMQPBindingsGraph.build(
            exchangeNames: exchanges.map(\.name),
            queueNames: queues.map(\.name),
            bindings: bindings.map {
                (
                    source: $0.source, destination: $0.destination,
                    destinationType: $0.destinationType, routingKey: $0.routingKey
                )
            })
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

    // MARK: - Create / delete actions

    func createQueue(_ spec: NewQueueSpec) async {
        guard let backend else { return }
        do {
            try await backend.createQueue(
                vhost: vhost, name: spec.name, durable: spec.durable, autoDelete: spec.autoDelete,
                arguments: spec.arguments)
            showingNewQueue = false
            await refresh()
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    func deleteQueue(_ queue: QueueInfo) async {
        guard let backend else { return }
        do {
            try await backend.deleteQueue(vhost: queue.vhost, name: queue.name)
            deleteQueueTarget = nil
            await refresh()
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    func createExchange(_ spec: NewExchangeSpec) async {
        guard let backend else { return }
        do {
            try await backend.createExchange(
                vhost: vhost, name: spec.name, type: spec.type, durable: spec.durable,
                autoDelete: spec.autoDelete)
            showingNewExchange = false
            await refresh()
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    func deleteExchange(_ exchange: ExchangeInfo) async {
        guard let backend else { return }
        do {
            try await backend.deleteExchange(vhost: exchange.vhost, name: exchange.name)
            deleteExchangeTarget = nil
            await refresh()
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    func createBinding(_ spec: NewBindingSpec) async {
        guard let backend else { return }
        do {
            try await backend.createBinding(
                vhost: vhost, source: spec.source, destination: spec.destination,
                routingKey: spec.routingKey)
            showingNewBinding = false
            await refresh()
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    func createPolicy(_ spec: NewPolicySpec) async {
        guard let backend else { return }
        do {
            try await backend.putPolicy(
                vhost: vhost, name: spec.name, pattern: spec.pattern, applyTo: spec.applyTo,
                definition: spec.definition, priority: spec.priorityValue)
            showingNewPolicy = false
            await refresh()
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    func deletePolicy(_ policy: PolicyInfo) async {
        guard let backend else { return }
        do {
            try await backend.deletePolicy(vhost: policy.vhost, name: policy.name)
            deletePolicyTarget = nil
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
