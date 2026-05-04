// Sources/SimpletonCore/Models/SessionState.swift
import Foundation

public struct WindowFrame: Codable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public enum PaneConnection: Codable, Equatable {
    case local(workingDirectory: String)
    case ssh(bookmarkId: UUID)

    private enum CodingKeys: String, CodingKey {
        case type, workingDirectory, bookmarkId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "local":
            let dir = try container.decode(String.self, forKey: .workingDirectory)
            self = .local(workingDirectory: dir)
        case "ssh":
            let id = try container.decode(UUID.self, forKey: .bookmarkId)
            self = .ssh(bookmarkId: id)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .local(let dir):
            try container.encode("local", forKey: .type)
            try container.encode(dir, forKey: .workingDirectory)
        case .ssh(let id):
            try container.encode("ssh", forKey: .type)
            try container.encode(id, forKey: .bookmarkId)
        }
    }
}

/// SplitNode variant for serialization that stores PaneConnection instead of PaneID
public indirect enum SessionSplitNode: Codable, Equatable {
    case pane(paneConn: PaneConnection)
    case split(direction: SplitDirection, children: [SessionSplitNode], ratios: [CGFloat])

    private enum CodingKeys: String, CodingKey {
        case type, connection, direction, children, ratios
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "pane":
            let conn = try container.decode(PaneConnection.self, forKey: .connection)
            self = .pane(paneConn: conn)
        case "split":
            let dir = try container.decode(SplitDirection.self, forKey: .direction)
            let children = try container.decode([SessionSplitNode].self, forKey: .children)
            let ratios = try container.decode([CGFloat].self, forKey: .ratios)
            self = .split(direction: dir, children: children, ratios: ratios)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pane(let conn):
            try container.encode("pane", forKey: .type)
            try container.encode(conn, forKey: .connection)
        case .split(let dir, let children, let ratios):
            try container.encode("split", forKey: .type)
            try container.encode(dir, forKey: .direction)
            try container.encode(children, forKey: .children)
            try container.encode(ratios, forKey: .ratios)
        }
    }
}

public struct TabState: Codable, Equatable {
    public let id: UUID
    public var title: String
    public var splitTree: SessionSplitNode

    public init(id: UUID = UUID(), title: String, splitTree: SessionSplitNode) {
        self.id = id
        self.title = title
        self.splitTree = splitTree
    }
}

public struct WindowState: Codable, Equatable {
    public let id: UUID
    public var frame: WindowFrame
    public var workspaceId: UUID?
    public var tabs: [TabState]

    public init(id: UUID = UUID(), frame: WindowFrame, workspaceId: UUID? = nil, tabs: [TabState]) {
        self.id = id
        self.frame = frame
        self.workspaceId = workspaceId
        self.tabs = tabs
    }
}

public struct SessionState: Codable, Equatable {
    public var cleanShutdown: Bool
    public var savedAt: Date
    public var windows: [WindowState]

    public init(cleanShutdown: Bool = false, savedAt: Date = Date(), windows: [WindowState] = []) {
        self.cleanShutdown = cleanShutdown
        self.savedAt = savedAt
        self.windows = windows
    }
}

public struct SessionStateFile: Codable {
    public let version: Int
    public var state: SessionState

    private enum CodingKeys: String, CodingKey {
        case version, cleanShutdown, savedAt, windows
    }

    public init(version: Int = 1, state: SessionState) {
        self.version = version
        self.state = state
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        let shutdown = try container.decode(Bool.self, forKey: .cleanShutdown)
        let savedAt = try container.decode(Date.self, forKey: .savedAt)
        let windows = try container.decode([WindowState].self, forKey: .windows)
        state = SessionState(cleanShutdown: shutdown, savedAt: savedAt, windows: windows)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(state.cleanShutdown, forKey: .cleanShutdown)
        try container.encode(state.savedAt, forKey: .savedAt)
        try container.encode(state.windows, forKey: .windows)
    }
}
