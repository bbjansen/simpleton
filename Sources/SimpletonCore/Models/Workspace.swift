// Sources/SimpletonCore/Models/Workspace.swift
import Foundation

public struct Workspace: Codable, Equatable {
    public var name: String
    public var savedAt: Date
    public var window: WindowState

    public init(name: String, savedAt: Date = Date(), window: WindowState) {
        self.name = name
        self.savedAt = savedAt
        self.window = window
    }
}

public struct WorkspaceFile: Codable {
    public let version: Int
    public var workspace: Workspace

    private enum CodingKeys: String, CodingKey {
        case version, name, savedAt, window
    }

    public init(version: Int = 1, workspace: Workspace) {
        self.version = version
        self.workspace = workspace
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        let name = try container.decode(String.self, forKey: .name)
        let savedAt = try container.decode(Date.self, forKey: .savedAt)
        let window = try container.decode(WindowState.self, forKey: .window)
        workspace = Workspace(name: name, savedAt: savedAt, window: window)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(workspace.name, forKey: .name)
        try container.encode(workspace.savedAt, forKey: .savedAt)
        try container.encode(workspace.window, forKey: .window)
    }
}
