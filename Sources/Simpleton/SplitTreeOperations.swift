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
        // Find the path to the pane
        guard let path = findPath(to: paneID, in: tree) else { return nil }

        // Walk up the path looking for a split in the matching axis
        for i in stride(from: path.count - 1, through: 0, by: -1) {
            let (node, childIndex) = path[i]
            if case .split(let splitDir, let children, _) = node {
                let matchesAxis =
                    (direction == .left || direction == .right) && splitDir == .vertical
                    || (direction == .up || direction == .down) && splitDir == .horizontal

                if matchesAxis {
                    let targetIndex: Int
                    switch direction {
                    case .left, .up:
                        targetIndex = childIndex - 1
                    case .right, .down:
                        targetIndex = childIndex + 1
                    }

                    if targetIndex >= 0 && targetIndex < children.count {
                        // Return the first pane in the target subtree (closest to the edge)
                        return firstPane(in: children[targetIndex])
                    }
                }
            }
        }
        return nil
    }

    /// Apply a predefined layout, creating new pane IDs as needed.
    /// Returns the new tree and list of all pane IDs in order.
    static func applyLayout(_ layout: PredefinedLayout, existingPaneID: PaneID) -> (SplitNode, [PaneID]) {
        var paneIDs: [PaneID] = []
        var isFirst = true

        func makeNode(from template: LayoutNode) -> SplitNode {
            switch template {
            case .pane:
                if isFirst {
                    isFirst = false
                    paneIDs.append(existingPaneID)
                    return .pane(existingPaneID)
                } else {
                    let newID = UUID()
                    paneIDs.append(newID)
                    return .pane(newID)
                }
            case .split(let dir, let children, let ratios):
                let childNodes = children.map { makeNode(from: $0) }
                return .split(direction: dir, children: childNodes, ratios: ratios)
            }
        }

        let tree = makeNode(from: layout.rootNode)
        return (tree, paneIDs)
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

    private static func replacingPane(
        in tree: SplitNode, target: PaneID, replacement: (PaneID) -> SplitNode
    ) -> SplitNode {
        switch tree {
        case .pane(let id):
            return id == target ? replacement(id) : tree
        case .split(let direction, let children, let ratios):
            let newChildren = children.map { replacingPane(in: $0, target: target, replacement: replacement) }
            return .split(direction: direction, children: newChildren, ratios: ratios)
        }
    }

    /// Returns the path from root to pane as [(node, childIndex)] pairs.
    private static func findPath(to paneID: PaneID, in tree: SplitNode) -> [(SplitNode, Int)]? {
        switch tree {
        case .pane(let id):
            return id == paneID ? [] : nil
        case .split(_, let children, _):
            for (index, child) in children.enumerated() {
                if let subPath = findPath(to: paneID, in: child) {
                    return [(tree, index)] + subPath
                }
            }
            return nil
        }
    }

    /// Returns the first pane ID found in depth-first traversal.
    private static func firstPane(in node: SplitNode) -> PaneID? {
        switch node {
        case .pane(let id): return id
        case .split(_, let children, _): return children.first.flatMap { firstPane(in: $0) }
        }
    }
}

// MARK: - Navigation Direction

enum NavigationDirection {
    case left, right, up, down
}
