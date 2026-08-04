// Sources/Simpleton/SessionCoordinator.swift
import AppKit
import SwiftUI
import SimpletonCore

final class SessionCoordinator {

    private let windowControllers: () -> [WindowController]
    private let config: () -> AppConfig
    private let theme: () -> Theme
    private let bookmarkStore: () -> BookmarkStore?
    private let sshConfigWatcher: () -> SSHConfigWatcher?
    private let pluginManager: () -> PluginManager?
    private let panelRegistry: () -> PanelRegistry?
    private let aiService: () -> AIService?
    private let skillStore: () -> SkillStore?
    private let memoryStore: () -> MemoryStore?
    private let mcpConfigStore: () -> MCPConfigStore?
    private let eventBus: () -> WorkspaceEventBus?
    private let workspaceManager: () -> WorkspaceManager?
    private let clearSavedState: () -> Void
    private let createNewWindow: () -> Void
    private let addWindowController: (WindowController) -> Void

    init(
        windowControllers: @escaping () -> [WindowController],
        config: @escaping () -> AppConfig,
        theme: @escaping () -> Theme,
        bookmarkStore: @escaping () -> BookmarkStore?,
        sshConfigWatcher: @escaping () -> SSHConfigWatcher?,
        pluginManager: @escaping () -> PluginManager?,
        panelRegistry: @escaping () -> PanelRegistry?,
        aiService: @escaping () -> AIService?,
        skillStore: @escaping () -> SkillStore?,
        memoryStore: @escaping () -> MemoryStore?,
        mcpConfigStore: @escaping () -> MCPConfigStore?,
        eventBus: @escaping () -> WorkspaceEventBus?,
        workspaceManager: @escaping () -> WorkspaceManager?,
        clearSavedState: @escaping () -> Void,
        createNewWindow: @escaping () -> Void,
        addWindowController: @escaping (WindowController) -> Void
    ) {
        self.windowControllers = windowControllers
        self.config = config
        self.theme = theme
        self.bookmarkStore = bookmarkStore
        self.sshConfigWatcher = sshConfigWatcher
        self.pluginManager = pluginManager
        self.panelRegistry = panelRegistry
        self.aiService = aiService
        self.skillStore = skillStore
        self.memoryStore = memoryStore
        self.mcpConfigStore = mcpConfigStore
        self.eventBus = eventBus
        self.workspaceManager = workspaceManager
        self.clearSavedState = clearSavedState
        self.createNewWindow = createNewWindow
        self.addWindowController = addWindowController
    }

    // MARK: - Capture

    func captureSessionState() -> SessionState {
        let windowStates = windowControllers().compactMap { wc -> WindowState? in
            guard let window = wc.window else { return nil }
            let frame = WindowFrame(
                x: Double(window.frame.origin.x),
                y: Double(window.frame.origin.y),
                width: Double(window.frame.width),
                height: Double(window.frame.height)
            )
            // Native AppKit tabs are separate NSWindows in the window's tab group — capture all of them.
            let tabWindows = window.tabGroup?.windows ?? [window]
            let tabs = tabWindows.compactMap { tabWin -> TabState? in
                guard let tc = tabWin.contentViewController as? TabContainerController else { return nil }
                return TabState(title: tabWin.title, splitTree: captureTree(from: tc.splitController))
            }
            guard !tabs.isEmpty else { return nil }
            return WindowState(frame: frame, tabs: tabs)
        }
        return SessionState(cleanShutdown: false, savedAt: Date(), windows: windowStates)
    }

    private func captureTree(from splitController: SplitController) -> SessionSplitNode {
        captureNode(splitController.tree, panes: splitController.panes)
    }

    private func captureNode(_ node: SplitNode, panes: [PaneID: PaneController]) -> SessionSplitNode {
        switch node {
        case .pane(let id):
            let connection: PaneConnection
            if let pane = panes[id] {
                switch pane.connectionType {
                case .local(_, let dir):
                    connection = .local(workingDirectory: dir)
                case .ssh(let bookmarkID):
                    connection = .ssh(bookmarkId: bookmarkID)
                }
            } else {
                connection = .local(workingDirectory: NSHomeDirectory())
            }
            return .pane(paneConn: connection)
        case .split(let dir, let children, let ratios):
            let childNodes = children.map { captureNode($0, panes: panes) }
            return .split(direction: dir, children: childNodes, ratios: ratios)
        }
    }

    // MARK: - Restore

    func showRestorePrompt(state: SessionState) {
        let alert = NSAlert()
        alert.messageText = "Restore previous session?"
        alert.informativeText = "Simpleton didn't shut down cleanly. Would you like to restore your previous windows and tabs?"
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Start Fresh")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            restoreSession(state: state)
        } else {
            clearSavedState()
            createNewWindow()
        }
    }

    func restoreSession(state: SessionState) {
        for windowState in state.windows {
            let wc = WindowController(config: config(), theme: theme())
            wc.bookmarkStore = bookmarkStore()
            wc.sshConfigWatcher = sshConfigWatcher()
            wc.pluginManager = pluginManager()
            wc.panelRegistry = panelRegistry()
            wc.aiService = aiService()
            wc.skillStore = skillStore()
            wc.memoryStore = memoryStore()
            wc.mcpConfigStore = mcpConfigStore()
            wc.eventBus = eventBus()
            addWindowController(wc)

            if let window = wc.window {
                let frame = NSRect(
                    x: windowState.frame.x,
                    y: windowState.frame.y,
                    width: windowState.frame.width,
                    height: windowState.frame.height
                )
                window.setFrame(frame, display: true)
            }

            if let firstTab = windowState.tabs.first,
               let tabContainer = wc.window?.contentViewController as? TabContainerController {
                restoreSplitTree(firstTab.splitTree, in: tabContainer)
            }
            // Recreate any additional tabs (native tab group) beyond the first.
            for extraTab in windowState.tabs.dropFirst() {
                let tabContainer = wc.newTab()
                restoreSplitTree(extraTab.splitTree, in: tabContainer)
            }

            wc.window?.makeKeyAndOrderFront(nil)
            wc.showWindow(nil)
        }

        if windowControllers().isEmpty {
            createNewWindow()
        }
    }

    private func restoreSplitTree(_ node: SessionSplitNode, in tabContainer: TabContainerController) {
        let sc = tabContainer.splitController
        guard let factory = sc.paneFactory else { return }

        // Materialize the saved layout into a live SplitNode with fresh pane IDs (nesting and ratios
        // preserved) plus its ordered leaves. This reconstructs any layout — a single pane, a flat
        // N-way split, or an arbitrarily nested tree — exactly as it was captured.
        let (tree, leaves) = node.materialize(makeID: { UUID() })
        guard let focusID = leaves.first?.id else { return }

        // Create one pane per leaf, then install the whole layout declaratively.
        var panes: [PaneID: PaneController] = [:]
        for leaf in leaves { panes[leaf.id] = factory(leaf.id) }
        sc.restore(tree: tree, panes: panes, focusedPaneID: focusID)

        // Restore each leaf's saved connection into its pane. Panes are created in the default
        // working directory, so a local leaf restarts its shell in the saved directory.
        for leaf in leaves {
            guard let pane = panes[leaf.id] else { continue }
            switch leaf.connection {
            case .ssh(let bookmarkId):
                Task { @MainActor [bookmarkStore, config] in
                    if let bookmark = await bookmarkStore()?.bookmark(for: bookmarkId) {
                        pane.startSSH(bookmark: bookmark, config: config())
                    }
                }
            case .local(let dir):
                if case .local(let shell, _) = pane.connectionType {
                    pane.restartShell(shell: shell, environment: pane.shellEnvironment, workingDirectory: dir)
                }
            }
        }
    }

    // MARK: - Workspaces

    func saveWorkspace() {
        guard let window = NSApp.keyWindow else { return }
        let alert = NSAlert()
        alert.messageText = "Save Workspace"
        alert.informativeText = "Enter a name for this workspace:"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        input.placeholderString = "Workspace name"
        alert.accessoryView = input
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, !input.stringValue.isEmpty else { return }
            let name = input.stringValue

            guard let self,
                  let tabContainer = window.contentViewController as? TabContainerController else { return }

            let frame = WindowFrame(
                x: Double(window.frame.origin.x),
                y: Double(window.frame.origin.y),
                width: Double(window.frame.width),
                height: Double(window.frame.height)
            )
            let splitTree = self.captureTree(from: tabContainer.splitController)
            let tab = TabState(title: window.title, splitTree: splitTree)
            let windowState = WindowState(frame: frame, tabs: [tab])
            let workspace = Workspace(name: name, window: windowState)
            try? self.workspaceManager()?.save(workspace: workspace)
        }
    }

    func openWorkspace(name: String) {
        guard let workspace = workspaceManager()?.load(name: name) else { return }
        let state = SessionState(windows: [workspace.window])
        restoreSession(state: state)
    }
}
