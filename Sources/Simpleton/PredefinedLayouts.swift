// Sources/Simpleton/PredefinedLayouts.swift
import Foundation
import SimpletonCore

/// Template node for layout definitions (no actual PaneIDs — those are assigned at apply time).
indirect enum LayoutNode {
    case pane
    case split(direction: SplitDirection, children: [LayoutNode], ratios: [CGFloat])

    var paneCount: Int {
        switch self {
        case .pane: return 1
        case .split(_, let children, _): return children.reduce(0) { $0 + $1.paneCount }
        }
    }
}

struct PredefinedLayout {
    let name: String
    let rootNode: LayoutNode
}

enum PredefinedLayouts {

    static let single = PredefinedLayout(
        name: "Single",
        rootNode: .pane
    )

    static let sideBySide = PredefinedLayout(
        name: "Side by Side",
        rootNode: .split(direction: .vertical, children: [.pane, .pane], ratios: [0.5, 0.5])
    )

    static let stacked = PredefinedLayout(
        name: "Stacked",
        rootNode: .split(direction: .horizontal, children: [.pane, .pane], ratios: [0.5, 0.5])
    )

    static let threeColumn = PredefinedLayout(
        name: "3 Column",
        rootNode: .split(direction: .vertical, children: [.pane, .pane, .pane], ratios: [0.333, 0.334, 0.333])
    )

    static let grid2x2 = PredefinedLayout(
        name: "Grid 2x2",
        rootNode: .split(direction: .horizontal, children: [
            .split(direction: .vertical, children: [.pane, .pane], ratios: [0.5, 0.5]),
            .split(direction: .vertical, children: [.pane, .pane], ratios: [0.5, 0.5]),
        ], ratios: [0.5, 0.5])
    )

    static let mainPlusSidebar = PredefinedLayout(
        name: "Main + Sidebar",
        rootNode: .split(direction: .vertical, children: [
            .pane,
            .split(direction: .horizontal, children: [.pane, .pane], ratios: [0.5, 0.5]),
        ], ratios: [0.67, 0.33])
    )

    static let mainPlusBottom = PredefinedLayout(
        name: "Main + Bottom",
        rootNode: .split(direction: .horizontal, children: [
            .pane,
            .split(direction: .vertical, children: [.pane, .pane], ratios: [0.5, 0.5]),
        ], ratios: [0.67, 0.33])
    )

    static let all: [PredefinedLayout] = [
        single, sideBySide, stacked, threeColumn, grid2x2, mainPlusSidebar, mainPlusBottom
    ]
}
