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
            guard let tabContainer = window.contentViewController as? TabContainerController else { return nil }
            let splitTree = captureTree(from: tabContainer.splitController)
            let tab = TabState(title: window.title, splitTree: splitTree)
            return WindowState(frame: frame, tabs: [tab])
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

            wc.window?.makeKeyAndOrderFront(nil)
            wc.showWindow(nil)
        }

        if windowControllers().isEmpty {
            createNewWindow()
        }
    }

    private func restoreSplitTree(_ node: SessionSplitNode, in tabContainer: TabContainerController) {
        switch node {
        case .pane(let conn):
            if case .ssh(let bookmarkId) = conn {
                Task { @MainActor [bookmarkStore] in
                    if let bookmark = await bookmarkStore()?.bookmark(for: bookmarkId) {
                        tabContainer.openSSHConnection(bookmark: bookmark)
                    }
                }
            }

        case .split(let direction, let children, _):
            if children.count >= 2 {
                for _ in 1..<children.count {
                    tabContainer.splitController.splitFocusedPane(direction: direction)
                }
                let paneIDs = tabContainer.splitController.tree.allPaneIDs
                for (index, child) in children.enumerated() {
                    if index < paneIDs.count, case .pane(let conn) = flattenFirstPane(child) {
                        if case .ssh(let bookmarkId) = conn {
                            Task { @MainActor [bookmarkStore, config] in
                                if let bookmark = await bookmarkStore()?.bookmark(for: bookmarkId),
                                   let pane = tabContainer.splitController.panes[paneIDs[index]] {
                                    pane.startSSH(bookmark: bookmark, config: config())
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func flattenFirstPane(_ node: SessionSplitNode) -> SessionSplitNode {
        switch node {
        case .pane: return node
        case .split(_, let children, _):
            return children.first.map { flattenFirstPane($0) } ?? node
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
