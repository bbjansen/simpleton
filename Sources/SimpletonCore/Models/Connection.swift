// Sources/SimpletonCore/Models/Connection.swift
import Foundation

/// The kind of service a `Connection` points at. Drives the panel's icon, default port, and
/// whether credentials are required. `.ssh` is reserved for a future migration of the SSH bookmark
/// system onto this generic model; it is unused in Phase 0.
public enum ConnectionKind: String, Codable, CaseIterable, Sendable {
    case postgres, mysql, sqlite, amqp, s3, ftp, sftp, ssh

    public var displayName: String {
        switch self {
        case .postgres: return "PostgreSQL"
        case .mysql: return "MySQL"
        case .sqlite: return "SQLite"
        case .amqp: return "RabbitMQ"
        case .s3: return "S3"
        case .ftp: return "FTP"
        case .sftp: return "SFTP"
        case .ssh: return "SSH"
        }
    }

    /// SF Symbol name for the connection's icon.
    public var icon: String {
        switch self {
        case .postgres, .mysql, .sqlite: return "cylinder.split.1x2"
        case .amqp: return "arrow.left.arrow.right"
        case .s3: return "externaldrive.connected.to.line.below"
        case .ftp, .sftp: return "folder.badge.gearshape"
        case .ssh: return "terminal"
        }
    }

    /// The conventional default port, or nil for file-based kinds (SQLite).
    public var defaultPort: Int? {
        switch self {
        case .postgres: return 5432
        case .mysql: return 3306
        case .amqp: return 5672
        case .s3: return 443
        case .ftp: return 21
        case .sftp, .ssh: return 22
        case .sqlite: return nil
        }
    }

    /// Whether this kind needs stored credentials. SQLite is a local file → no credentials.
    public var requiresCredentials: Bool { self != .sqlite }
}

/// A saved, backend-agnostic connection to a service surfaced by a client-viewer panel. Shared
/// substrate for the DB / MQ / object-storage / file-transfer clients; the SSH `Bookmark` system is
/// separate and untouched. Secrets are NOT stored here — they live in `CredentialStore`, keyed by `id`.
public struct Connection: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: ConnectionKind
    public var host: String?
    public var port: Int?
    public var username: String?
    /// Kind-specific extra fields (e.g. "database", S3 "region"/"bucket"/"endpoint", "useTLS").
    public var params: [String: String]
    public var tags: [String]
    public var pinned: Bool
    public var createdAt: Date
    public var updatedAt: Date
    /// Env-safety accent, one of the app accent names (red/orange/yellow/green/blue/purple/pink/graphite).
    /// Convention: prod = red. Nil = no color.
    public var color: String?
    /// Single-level group name (e.g. "prod"). Nil = ungrouped. Nested groups are a later enhancement.
    public var group: String?
    /// References an SSH `Bookmark` (by id) to tunnel this connection through a bastion. Nil = direct.
    public var tunnelBookmarkID: UUID?

    public init(
        id: UUID = UUID(),
        name: String,
        kind: ConnectionKind,
        host: String? = nil,
        port: Int? = nil,
        username: String? = nil,
        params: [String: String] = [:],
        tags: [String] = [],
        pinned: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        color: String? = nil,
        group: String? = nil,
        tunnelBookmarkID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.host = host
        self.port = port
        self.username = username
        self.params = params
        self.tags = tags
        self.pinned = pinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.color = color
        self.group = group
        self.tunnelBookmarkID = tunnelBookmarkID
    }

    /// Tolerant decoding: any key missing from an older connections.json falls back to a default,
    /// so adding fields never drops a user's existing connections (matches the project convention).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        kind = try c.decodeIfPresent(ConnectionKind.self, forKey: .kind) ?? .postgres
        host = try c.decodeIfPresent(String.self, forKey: .host)
        port = try c.decodeIfPresent(Int.self, forKey: .port)
        username = try c.decodeIfPresent(String.self, forKey: .username)
        params = try c.decodeIfPresent([String: String].self, forKey: .params) ?? [:]
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        color = try c.decodeIfPresent(String.self, forKey: .color)
        group = try c.decodeIfPresent(String.self, forKey: .group)
        tunnelBookmarkID = try c.decodeIfPresent(UUID.self, forKey: .tunnelBookmarkID)
    }
}

/// Secret material for a `Connection`, stored in the Keychain by `CredentialStore` (never in
/// connections.json). Several optional fields because different kinds need different secrets
/// (e.g. S3 needs an access key + secret key; a database needs a password).
public struct ConnectionSecret: Codable, Equatable, Sendable {
    public var password: String?
    public var accessKey: String?
    public var secretKey: String?
    public var token: String?
    public var passphrase: String?

    public init(
        password: String? = nil,
        accessKey: String? = nil,
        secretKey: String? = nil,
        token: String? = nil,
        passphrase: String? = nil
    ) {
        self.password = password
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.token = token
        self.passphrase = passphrase
    }
}
