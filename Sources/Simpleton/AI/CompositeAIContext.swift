// Sources/Simpleton/AI/CompositeAIContext.swift
import Foundation
import SimpletonCore

/// Snapshot of a single pane's state at a point in time.
struct PaneSnapshot {
    let paneID: PaneID
    let label: String
    let paneNumber: Int
    let cwd: String?
    let shell: String?
    let recentOutput: String?
    let isFocused: Bool
    let connectionType: ConnectionType
}

/// Aggregated context from all panes in a tab.
struct CompositeAIContext {
    let os: String
    let panes: [PaneSnapshot]
    let focusedPaneID: PaneID

    /// Ordered pane IDs matching pane numbers (paneOrder[0] = Pane 1).
    var paneOrder: [PaneID] { panes.map(\.paneID) }

    /// Resolve a 1-based pane number to a PaneID. Returns nil if out of range.
    func resolvePaneNumber(_ number: Int) -> PaneID? {
        let index = number - 1
        guard index >= 0, index < panes.count else { return nil }
        return panes[index].paneID
    }
}
