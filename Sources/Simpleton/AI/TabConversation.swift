import Combine
// Sources/Simpleton/AI/TabConversation.swift
import Foundation
import SimpletonCore

@MainActor
final class TabConversation: ObservableObject {
    let tabID: UUID

    @Published var messages: [ChatMessage] = []
    @Published var agentBubbles: [AgentUIMessage] = []
    @Published var activeSession: AgentSession?
    @Published var isRunning = false
    @Published var targetPaneID: PaneID?
    @Published var watchSession: WatchSession?

    /// Ordered pane IDs from depth-first traversal. paneOrder[0] = "Pane 1".
    @Published var paneOrder: [PaneID] = []

    /// Human-readable labels keyed by PaneID.
    @Published var paneLabels: [PaneID: String] = [:]

    private weak var splitController: SplitController?
    private(set) weak var aiService: AIService?

    init(tabID: UUID, splitController: SplitController, aiService: AIService?) {
        self.tabID = tabID
        self.splitController = splitController
        self.aiService = aiService
        rebuildPaneLabels()
    }

    // MARK: - Pane Labels

    func rebuildPaneLabels() {
        guard let sc = splitController else {
            paneOrder = []
            paneLabels = [:]
            return
        }
        let ids = sc.tree.allPaneIDs
        paneOrder = ids

        var labels: [PaneID: String] = [:]
        for (index, paneID) in ids.enumerated() {
            guard let pane = sc.panes[paneID] else { continue }
            labels[paneID] = AIContextBuilder.paneLabel(for: pane, number: index + 1)
        }
        paneLabels = labels
    }

    // MARK: - Context

    func buildCompositeContext() -> CompositeAIContext? {
        guard let sc = splitController else { return nil }
        return AIContextBuilder.buildComposite(splitController: sc)
    }

    // MARK: - Pane Routing

    /// Resolve a 1-based pane number to a PaneController. Falls back to focused pane.
    func resolvePane(number: Int?) -> (pane: PaneController, label: String, wasFallback: Bool)? {
        guard let sc = splitController else { return nil }

        if let num = number, num >= 1, num <= paneOrder.count {
            let paneID = paneOrder[num - 1]
            if let pane = sc.panes[paneID] {
                return (pane, paneLabels[paneID] ?? "Pane \(num)", false)
            }
        }

        // Fallback to focused pane
        let focusedID = sc.focusedPaneID
        if let pane = sc.panes[focusedID] {
            let label = paneLabels[focusedID] ?? "Pane"
            let isFallback = number != nil
            return (pane, label, isFallback)
        }

        return nil
    }

    /// Send a command string to a specific pane's terminal.
    func routeCommand(_ cmd: String, to paneID: PaneID) {
        guard let sc = splitController, let pane = sc.panes[paneID] else { return }
        let bytes = Array(cmd.utf8)
        pane.terminalView.send(data: bytes[...])
    }

    // MARK: - Session Management

    func cancel() {
        activeSession?.cancel()
        isRunning = false
        activeSession = nil
    }
}
