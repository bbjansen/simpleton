// Sources/Simpleton/SplitTreeOperations.swift
import Foundation
import SimpletonCore

enum SplitTreeOperations {

    /// Split an existing pane into two. Returns the new tree and the new pane's ID.
    /// The original pane becomes the first child; a new pane becomes the second.
    static func splitPane(
        in tree: SplitNode,
        paneID: PaneID,
        direction: SplitDirection,
        newPaneID: PaneID = UUID()
    ) -> (SplitNode, PaneID) {
        let newTree = replacingPane(in: tree, target: paneID) { _ in
            .split(direction: direction, children: [.pane(paneID), .pane(newPaneID)], ratios: [0.5, 0.5])
        }
        return (newTree, newPaneID)
    }

    /// Remove a pane from the tree. If removing leaves a split with one child,
    /// that child is promoted up. Returns nil if the tree becomes empty.
    static func closePane(in tree: SplitNode, paneID: PaneID) -> SplitNode? {
        switch tree {
        case .pane(let id):
            return id == paneID ? nil : tree
        case .split(let direction, let children, let ratios):
            var newChildren: [SplitNode] = []
            var newRatios: [CGFloat] = []

            for (index, child) in children.enumerated() {
                if let remaining = closePane(in: child, paneID: paneID) {
                    newChildren.append(remaining)
                    newRatios.append(ratios[index])
                }
            }

            if newChildren.isEmpty {
                return nil
            } else if newChildren.count == 1 {
                // Promote the single remaining child
                return newChildren[0]
            } else {
                // Normalize ratios to sum to 1.0
                let total = newRatios.reduce(0, +)
                let normalized = total > 0 ? newRatios.map { $0 / total } : newRatios
                return .split(direction: direction, children: newChildren, ratios: normalized)
            }
        }
    }

    /// Find the pane adjacent to the given pane in the specified direction.
    /// Returns nil if there is no adjacent pane in that direction.
    static func adjacentPane(
        in tree: SplitNode,
        from paneID: PaneID,
        direction: NavigationDirection
    ) -> PaneID? {
        let flatPanes = flattenPanes(tree: tree, direction: direction)
        guard let index = flatPanes.firstIndex(of: paneID) else { return nil }

        switch direction {
        case .left, .up:
            return index > 0 ? flatPanes[index - 1] : nil
        case .right, .down:
            return index < flatPanes.count - 1 ? flatPanes[index + 1] : nil
        }
    }

    /// Apply a predefined layout, creating new pane IDs as needed.
    /// Returns the new tree and list of all pane IDs in order.
    static func applyLayout(_ layout: PredefinedLayout, existingPaneID: PaneID) -> (SplitNode, [PaneID]) {
        var paneIDs: [PaneID] = [existingPaneID]

        func makeNode(from template: LayoutNode) -> SplitNode {
            switch template {
            case .pane:
                if paneIDs.count <= template.paneCount {
                    let newID = UUID()
                    paneIDs.append(newID)
                    return .pane(newID)
                }
                return .pane(paneIDs[0]) // First pane reuses existing
            case .split(let dir, let children, let ratios):
                let childNodes = children.map { makeNode(from: $0) }
                return .split(direction: dir, children: childNodes, ratios: ratios)
            }
        }

        // Build the tree, using existingPaneID for the first pane
        let tree = makeNode(from: layout.rootNode)

        // Collect all pane IDs from the built tree
        let allIDs = tree.allPaneIDs
        return (tree, allIDs)
    }

    /// Update ratios for a split containing the given pane.
    static func updateRatios(in tree: SplitNode, splitContaining paneID: PaneID, newRatios: [CGFloat]) -> SplitNode {
        switch tree {
        case .pane:
            return tree
        case .split(let direction, let children, let ratios):
            if children.contains(where: { node in
                if case .pane(let id) = node { return id == paneID }
                return false
            }) {
                return .split(direction: direction, children: children, ratios: newRatios)
            }
            let updatedChildren = children.map { updateRatios(in: $0, splitContaining: paneID, newRatios: newRatios) }
            return .split(direction: direction, children: updatedChildren, ratios: ratios)
        }
    }

    // MARK: - Helpers

    private static func replacingPane(in tree: SplitNode, target: PaneID, replacement: (PaneID) -> SplitNode) -> SplitNode {
        switch tree {
        case .pane(let id):
            return id == target ? replacement(id) : tree
        case .split(let direction, let children, let ratios):
            let newChildren = children.map { replacingPane(in: $0, target: target, replacement: replacement) }
            return .split(direction: direction, children: newChildren, ratios: ratios)
        }
    }

    /// Flatten pane IDs in traversal order appropriate for the navigation direction.
    private static func flattenPanes(tree: SplitNode, direction: NavigationDirection) -> [PaneID] {
        switch tree {
        case .pane(let id):
            return [id]
        case .split(let splitDir, let children, _):
            let isRelevantAxis = (direction == .left || direction == .right) && splitDir == .vertical
                || (direction == .up || direction == .down) && splitDir == .horizontal
            if isRelevantAxis {
                return children.flatMap { flattenPanes(tree: $0, direction: direction) }
            } else {
                // For perpendicular splits, just flatten all children
                return children.flatMap { flattenPanes(tree: $0, direction: direction) }
            }
        }
    }
}

// MARK: - Navigation Direction

enum NavigationDirection {
    case left, right, up, down
}
