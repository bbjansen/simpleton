// Sources/SimpletonAMQP/AMQPManagement.swift
import Foundation

/// The management-plane interface every AMQP backend implements. All I/O is async and runs off the
/// main actor; backends map every failure to `AMQPError` so no raw transport error escapes. Mirrors
/// the shape of `SimpletonSQL`'s `SQLDriver` seam.
public protocol AMQPManagementBackend: AnyObject, Sendable {
    /// Broker overview (versions + coarse totals). Doubles as a connectivity probe.
    func overview() async throws -> Overview
    /// Queues in a virtual host (default vhost is `/`).
    func queues(vhost: String) async throws -> [QueueInfo]
    /// Exchanges in a virtual host.
    func exchanges(vhost: String) async throws -> [ExchangeInfo]
    /// All client connections to the broker (across vhosts).
    func connections() async throws -> [ConnectionInfo]
    /// All channels on the broker (across vhosts).
    func channels() async throws -> [ChannelInfo]
    /// Peek up to `count` messages from a queue. Non-destructive: uses `ack_requeue_true`, so the
    /// messages are requeued rather than consumed.
    func getMessages(vhost: String, queue: String, count: Int) async throws -> [MessagePreview]
    /// Publish a message to an exchange. Returns whether the broker routed it to at least one queue.
    @discardableResult
    func publish(vhost: String, exchange: String, routingKey: String, payload: String) async throws -> Bool
    /// Purge (delete all messages from) a queue.
    func purge(vhost: String, queue: String) async throws
}

// MARK: - Model

/// Broker overview. Only the fields the panel surfaces are decoded; the management payload has more.
public struct Overview: Sendable, Codable, Equatable {
    public let rabbitmqVersion: String
    public let erlangVersion: String
    public let totalMessages: Int
    public let totalMessagesReady: Int
    public let totalMessagesUnacked: Int
    public let totalConnections: Int
    public let totalQueues: Int

    public init(
        rabbitmqVersion: String, erlangVersion: String, totalMessages: Int, totalMessagesReady: Int,
        totalMessagesUnacked: Int, totalConnections: Int, totalQueues: Int
    ) {
        self.rabbitmqVersion = rabbitmqVersion
        self.erlangVersion = erlangVersion
        self.totalMessages = totalMessages
        self.totalMessagesReady = totalMessagesReady
        self.totalMessagesUnacked = totalMessagesUnacked
        self.totalConnections = totalConnections
        self.totalQueues = totalQueues
    }

    private enum CodingKeys: String, CodingKey {
        case rabbitmqVersion = "rabbitmq_version"
        case erlangVersion = "erlang_version"
        case queueTotals = "queue_totals"
        case objectTotals = "object_totals"
    }

    private enum QueueTotalsKeys: String, CodingKey {
        case messages
        case messagesReady = "messages_ready"
        case messagesUnacknowledged = "messages_unacknowledged"
    }

    private enum ObjectTotalsKeys: String, CodingKey {
        case connections
        case queues
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rabbitmqVersion = try c.decodeIfPresent(String.self, forKey: .rabbitmqVersion) ?? ""
        erlangVersion = try c.decodeIfPresent(String.self, forKey: .erlangVersion) ?? ""
        let qt = try? c.nestedContainer(keyedBy: QueueTotalsKeys.self, forKey: .queueTotals)
        totalMessages = try qt?.decodeIfPresent(Int.self, forKey: .messages) ?? 0
        totalMessagesReady = try qt?.decodeIfPresent(Int.self, forKey: .messagesReady) ?? 0
        totalMessagesUnacked = try qt?.decodeIfPresent(Int.self, forKey: .messagesUnacknowledged) ?? 0
        let ot = try? c.nestedContainer(keyedBy: ObjectTotalsKeys.self, forKey: .objectTotals)
        totalConnections = try ot?.decodeIfPresent(Int.self, forKey: .connections) ?? 0
        totalQueues = try ot?.decodeIfPresent(Int.self, forKey: .queues) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rabbitmqVersion, forKey: .rabbitmqVersion)
        try c.encode(erlangVersion, forKey: .erlangVersion)
        var qt = c.nestedContainer(keyedBy: QueueTotalsKeys.self, forKey: .queueTotals)
        try qt.encode(totalMessages, forKey: .messages)
        try qt.encode(totalMessagesReady, forKey: .messagesReady)
        try qt.encode(totalMessagesUnacked, forKey: .messagesUnacknowledged)
        var ot = c.nestedContainer(keyedBy: ObjectTotalsKeys.self, forKey: .objectTotals)
        try ot.encode(totalConnections, forKey: .connections)
        try ot.encode(totalQueues, forKey: .queues)
    }
}

/// One queue as reported by `/api/queues`. Rates come from the optional `message_stats` block.
public struct QueueInfo: Sendable, Codable, Equatable, Identifiable {
    public let name: String
    public let vhost: String
    public let messages: Int
    public let messagesReady: Int
    public let messagesUnacked: Int
    public let consumers: Int
    public let state: String
    public let node: String
    public let publishRate: Double?
    public let deliverRate: Double?

    /// Stable identity for SwiftUI lists: vhost + name is unique within a broker.
    public var id: String { "\(vhost)/\(name)" }

    public init(
        name: String, vhost: String, messages: Int, messagesReady: Int, messagesUnacked: Int,
        consumers: Int, state: String, node: String, publishRate: Double? = nil, deliverRate: Double? = nil
    ) {
        self.name = name
        self.vhost = vhost
        self.messages = messages
        self.messagesReady = messagesReady
        self.messagesUnacked = messagesUnacked
        self.consumers = consumers
        self.state = state
        self.node = node
        self.publishRate = publishRate
        self.deliverRate = deliverRate
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case vhost
        case messages
        case messagesReady = "messages_ready"
        case messagesUnacked = "messages_unacknowledged"
        case consumers
        case state
        case node
        case messageStats = "message_stats"
    }

    private enum StatsKeys: String, CodingKey {
        case publishDetails = "publish_details"
        case deliverGetDetails = "deliver_get_details"
    }

    private enum RateKeys: String, CodingKey {
        case rate
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        vhost = try c.decodeIfPresent(String.self, forKey: .vhost) ?? "/"
        messages = try c.decodeIfPresent(Int.self, forKey: .messages) ?? 0
        messagesReady = try c.decodeIfPresent(Int.self, forKey: .messagesReady) ?? 0
        messagesUnacked = try c.decodeIfPresent(Int.self, forKey: .messagesUnacked) ?? 0
        consumers = try c.decodeIfPresent(Int.self, forKey: .consumers) ?? 0
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? ""
        node = try c.decodeIfPresent(String.self, forKey: .node) ?? ""
        if let stats = try? c.nestedContainer(keyedBy: StatsKeys.self, forKey: .messageStats) {
            let pub = try? stats.nestedContainer(keyedBy: RateKeys.self, forKey: .publishDetails)
            publishRate = try pub?.decodeIfPresent(Double.self, forKey: .rate)
            let del = try? stats.nestedContainer(keyedBy: RateKeys.self, forKey: .deliverGetDetails)
            deliverRate = try del?.decodeIfPresent(Double.self, forKey: .rate)
        } else {
            publishRate = nil
            deliverRate = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(vhost, forKey: .vhost)
        try c.encode(messages, forKey: .messages)
        try c.encode(messagesReady, forKey: .messagesReady)
        try c.encode(messagesUnacked, forKey: .messagesUnacked)
        try c.encode(consumers, forKey: .consumers)
        try c.encode(state, forKey: .state)
        try c.encode(node, forKey: .node)
        if publishRate != nil || deliverRate != nil {
            var stats = c.nestedContainer(keyedBy: StatsKeys.self, forKey: .messageStats)
            if let publishRate {
                var pub = stats.nestedContainer(keyedBy: RateKeys.self, forKey: .publishDetails)
                try pub.encode(publishRate, forKey: .rate)
            }
            if let deliverRate {
                var del = stats.nestedContainer(keyedBy: RateKeys.self, forKey: .deliverGetDetails)
                try del.encode(deliverRate, forKey: .rate)
            }
        }
    }
}

/// One exchange as reported by `/api/exchanges`. The default (nameless) exchange has an empty name.
public struct ExchangeInfo: Sendable, Codable, Equatable, Identifiable {
    public let name: String
    public let type: String
    public let durable: Bool
    public let autoDelete: Bool
    public let vhost: String

    public var id: String { "\(vhost)/\(name.isEmpty ? "(default)" : name)" }

    public init(name: String, type: String, durable: Bool, autoDelete: Bool, vhost: String = "/") {
        self.name = name
        self.type = type
        self.durable = durable
        self.autoDelete = autoDelete
        self.vhost = vhost
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case type
        case durable
        case autoDelete = "auto_delete"
        case vhost
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        durable = try c.decodeIfPresent(Bool.self, forKey: .durable) ?? false
        autoDelete = try c.decodeIfPresent(Bool.self, forKey: .autoDelete) ?? false
        vhost = try c.decodeIfPresent(String.self, forKey: .vhost) ?? "/"
    }
}

/// One client connection as reported by `/api/connections`.
public struct ConnectionInfo: Sendable, Codable, Equatable, Identifiable {
    public let name: String
    public let user: String
    public let state: String
    public let channels: Int
    public let recvOct: Int?
    public let sendOct: Int?

    public var id: String { name }

    public init(name: String, user: String, state: String, channels: Int, recvOct: Int? = nil, sendOct: Int? = nil) {
        self.name = name
        self.user = user
        self.state = state
        self.channels = channels
        self.recvOct = recvOct
        self.sendOct = sendOct
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case user
        case state
        case channels
        case recvOct = "recv_oct"
        case sendOct = "send_oct"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        user = try c.decodeIfPresent(String.self, forKey: .user) ?? ""
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? ""
        channels = try c.decodeIfPresent(Int.self, forKey: .channels) ?? 0
        recvOct = try c.decodeIfPresent(Int.self, forKey: .recvOct)
        sendOct = try c.decodeIfPresent(Int.self, forKey: .sendOct)
    }
}

/// One channel as reported by `/api/channels`.
public struct ChannelInfo: Sendable, Codable, Equatable, Identifiable {
    public let name: String
    public let number: Int
    public let consumerCount: Int
    public let unacked: Int
    public let prefetch: Int
    public let state: String

    public var id: String { name }

    public init(name: String, number: Int, consumerCount: Int, unacked: Int, prefetch: Int, state: String) {
        self.name = name
        self.number = number
        self.consumerCount = consumerCount
        self.unacked = unacked
        self.prefetch = prefetch
        self.state = state
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case number
        case consumerCount = "consumer_count"
        case unacked = "messages_unacknowledged"
        case prefetch = "prefetch_count"
        case state
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        number = try c.decodeIfPresent(Int.self, forKey: .number) ?? 0
        consumerCount = try c.decodeIfPresent(Int.self, forKey: .consumerCount) ?? 0
        unacked = try c.decodeIfPresent(Int.self, forKey: .unacked) ?? 0
        prefetch = try c.decodeIfPresent(Int.self, forKey: .prefetch) ?? 0
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? ""
    }
}

/// A peeked message from `/api/queues/.../get`. `payload` is always decoded to a display string
/// (base64 payloads are decoded to UTF-8 when possible; `payloadBytes` is the raw byte length).
public struct MessagePreview: Sendable, Codable, Equatable {
    public let payload: String
    public let payloadBytes: Int
    public let routingKey: String
    public let redelivered: Bool
    public let properties: [String: String]

    public init(
        payload: String, payloadBytes: Int, routingKey: String, redelivered: Bool,
        properties: [String: String]
    ) {
        self.payload = payload
        self.payloadBytes = payloadBytes
        self.routingKey = routingKey
        self.redelivered = redelivered
        self.properties = properties
    }

    private enum CodingKeys: String, CodingKey {
        case payload
        case payloadBytes = "payload_bytes"
        case payloadEncoding = "payload_encoding"
        case routingKey = "routing_key"
        case redelivered
        case properties
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawPayload = try c.decodeIfPresent(String.self, forKey: .payload) ?? ""
        let encoding = try c.decodeIfPresent(String.self, forKey: .payloadEncoding) ?? "string"
        payload = MessagePreview.decodePayload(rawPayload, encoding: encoding)
        payloadBytes = try c.decodeIfPresent(Int.self, forKey: .payloadBytes) ?? rawPayload.utf8.count
        routingKey = try c.decodeIfPresent(String.self, forKey: .routingKey) ?? ""
        redelivered = try c.decodeIfPresent(Bool.self, forKey: .redelivered) ?? false
        // Properties are an arbitrary JSON object; flatten scalar values to strings for display.
        if let props = try? c.decodeIfPresent([String: AMQPScalar].self, forKey: .properties) {
            properties = props.mapValues { $0.displayString }
        } else {
            properties = [:]
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(payload, forKey: .payload)
        try c.encode(payloadBytes, forKey: .payloadBytes)
        try c.encode("string", forKey: .payloadEncoding)
        try c.encode(routingKey, forKey: .routingKey)
        try c.encode(redelivered, forKey: .redelivered)
    }

    /// Decode a management-API payload string. `base64` payloads are decoded to UTF-8 when the bytes
    /// are valid text; otherwise a byte-count placeholder is shown so binary payloads don't render as
    /// mojibake. `string`/`auto` payloads pass through unchanged.
    public static func decodePayload(_ raw: String, encoding: String) -> String {
        guard encoding == "base64" else { return raw }
        guard let data = Data(base64Encoded: raw) else { return raw }
        if let text = String(data: data, encoding: .utf8) { return text }
        return "<\(data.count) bytes binary>"
    }
}

/// A scalar JSON value used only to flatten a message's `properties` object into `[String:String]`.
enum AMQPScalar: Sendable, Decodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    var displayString: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? c.decode(Int.self) {
            self = .int(i)
        } else if let d = try? c.decode(Double.self) {
            self = .double(d)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else {
            // Nested objects/arrays (e.g. a headers table) render as a compact placeholder rather
            // than failing the whole decode.
            self = .string("…")
        }
    }
}

// MARK: - Errors

public enum AMQPError: Error, Sendable, Equatable {
    /// DNS / TLS / socket failure reaching the management API.
    case connectionFailed(String)
    /// 401 or 403 — bad user/password or insufficient permissions.
    case auth(String)
    /// 404 — vhost, queue, or exchange does not exist.
    case notFound(String)
    /// Any other non-2xx response, with the HTTP status and body.
    case requestFailed(status: Int, body: String)
    /// The response body could not be decoded as the expected JSON.
    case decodeFailed(String)
    /// The connection kind is not `.amqp`.
    case unsupported(String)

    /// A short, user-facing description for the panel's error banner.
    public var message: String {
        switch self {
        case .connectionFailed(let m): return m
        case .auth(let m): return m
        case .notFound(let m): return m
        case .requestFailed(let status, let body):
            return "HTTP \(status)\(body.isEmpty ? "" : ": \(body)")"
        case .decodeFailed(let m): return m
        case .unsupported(let m): return m
        }
    }
}
