// Sources/SimpletonCore/Models/SplitNode.swift
import Foundation

public typealias PaneID = UUID

public enum SplitDirection: String, Codable, Equatable {
    case horizontal // ── divider, top/bottom panes
    case vertical   // │ divider, left/right panes
}

public indirect enum SplitNode: Codable, Equatable {
    case pane(PaneID)
    case split(direction: SplitDirection, children: [SplitNode], ratios: [CGFloat])

    private enum CodingKeys: String, CodingKey {
        case type, id, direction, children, ratios
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "pane":
            let id = try container.decode(PaneID.self, forKey: .id)
            self = .pane(id)
        case "split":
            let direction = try container.decode(SplitDirection.self, forKey: .direction)
            let children = try container.decode([SplitNode].self, forKey: .children)
            let ratios = try container.decode([CGFloat].self, forKey: .ratios)
            self = .split(direction: direction, children: children, ratios: ratios)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pane(let id):
            try container.encode("pane", forKey: .type)
            try container.encode(id, forKey: .id)
        case .split(let direction, let children, let ratios):
            try container.encode("split", forKey: .type)
            try container.encode(direction, forKey: .direction)
            try container.encode(children, forKey: .children)
            try container.encode(ratios, forKey: .ratios)
        }
    }

    public var allPaneIDs: [PaneID] {
        switch self {
        case .pane(let id): return [id]
        case .split(_, let children, _): return children.flatMap(\.allPaneIDs)
        }
    }

    public var paneCount: Int {
        switch self {
        case .pane: return 1
        case .split(_, let children, _): return children.reduce(0) { $0 + $1.paneCount }
        }
    }
}
