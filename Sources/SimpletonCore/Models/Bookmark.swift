// Sources/SimpletonCore/Models/Bookmark.swift
import Foundation

public enum AuthMethod: Codable, Equatable {
    case key(identityFile: String)
    case password
    case agent
    case none

    private enum CodingKeys: String, CodingKey {
        case method, identityFile
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let method = try container.decode(String.self, forKey: .method)
        switch method {
        case "key":
            let file = try container.decode(String.self, forKey: .identityFile)
            self = .key(identityFile: file)
        case "password": self = .password
        case "agent": self = .agent
        case "none": self = .none
        default: self = .none
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .key(let file):
            try container.encode("key", forKey: .method)
            try container.encode(file, forKey: .identityFile)
        case .password:
            try container.encode("password", forKey: .method)
        case .agent:
            try container.encode("agent", forKey: .method)
        case .none:
            try container.encode("none", forKey: .method)
        }
    }
}

public enum PortForwardDirection: String, Codable, Equatable {
    case local
    case remote
}

public struct PortForward: Codable, Equatable {
    public let direction: PortForwardDirection
    public let localPort: Int
    public let remoteHost: String
    public let remotePort: Int

    public init(direction: PortForwardDirection, localPort: Int, remoteHost: String, remotePort: Int) {
        self.direction = direction
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
    }
}

public struct Bookmark: Codable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var user: String?
    public var auth: AuthMethod
    public var jumpHosts: [String]
    public var portForwards: [PortForward]
    public var tags: [String]
    public var notes: String
    public var pinned: Bool
    public var sshConfigHost: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 22,
        user: String? = nil,
        auth: AuthMethod = .agent,
        jumpHosts: [String] = [],
        portForwards: [PortForward] = [],
        tags: [String] = [],
        notes: String = "",
        pinned: Bool = false,
        sshConfigHost: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.user = user
        self.auth = auth
        self.jumpHosts = jumpHosts
        self.portForwards = portForwards
        self.tags = tags
        self.notes = notes
        self.pinned = pinned
        self.sshConfigHost = sshConfigHost
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct BookmarkFile: Codable {
    public let version: Int
    public var bookmarks: [Bookmark]

    public init(version: Int = 1, bookmarks: [Bookmark] = []) {
        self.version = version
        self.bookmarks = bookmarks
    }
}
