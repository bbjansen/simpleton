// Sources/Simpleton/WindowController.swift
import AppKit
import SimpletonCore

/// Manages one window. Each window contains one or more tabs (via native AppKit tabbing).
/// Each tab has its own TabContainerController with its own split tree.
final class WindowController: NSWindowController, NSWindowDelegate {

    private let config: AppConfig
    private let theme: Theme
    private var tabContainer: TabContainerController

    /// Set these after init to propagate to all TabContainerControllers.
    var bookmarkStore: BookmarkStore? {
        didSet { tabContainer.bookmarkStore = bookmarkStore }
    }
    var sshConfigWatcher: SSHConfigWatcher? {
        didSet { tabContainer.sshConfigWatcher = sshConfigWatcher }
    }
    var pluginManager: PluginManager? {
        didSet { tabContainer.pluginManager = pluginManager }
    }
    var panelRegistry: PanelRegistry? {
        didSet { tabContainer.panelRegistry = panelRegistry }
    }
    var aiService: AIService? {
        didSet { tabContainer.aiService = aiService }
    }
    var skillStore: SkillStore? {
        didSet { tabContainer.skillStore = skillStore }
    }
    var memoryStore: MemoryStore? {
        didSet { tabContainer.memoryStore = memoryStore }
    }
    var mcpConfigStore: MCPConfigStore? {
        didSet { tabContainer.mcpConfigStore = mcpConfigStore }
    }
    var eventBus: WorkspaceEventBus? {
        didSet { tabContainer.eventBus = eventBus }
    }

    init(config: AppConfig, theme: Theme) {
        self.config = config
        self.theme = theme

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Simpleton"
        window.minSize = NSSize(width: 400, height: 300)
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "com.simpleton.terminal"
        window.appearance = NSAppearance(named: .darkAqua)

        self.tabContainer = TabContainerController(config: config, theme: theme)

        super.init(window: window)

        window.contentViewController = tabContainer
        window.delegate = self

        // Wire close-pane to close window when last pane closes
        tabContainer.splitController.onPaneClose = { [weak self] _ in
            self?.window?.close()
        }

        // Wire focus change to update window title
        tabContainer.splitController.onFocusChange = { [weak self] paneID in
            guard let pane = self?.tabContainer.splitController.panes[paneID] else { return }
            pane.onTitleChange = { title in
                self?.window?.title = title
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Public API

    /// The active split controller (for the current tab).
    var activeSplitController: SplitController {
        tabContainer.splitController
    }

    /// Create a new tab in this window.
    func newTab() {
        let newTabContainer = TabContainerController(config: config, theme: theme)
        newTabContainer.bookmarkStore = bookmarkStore
        newTabContainer.sshConfigWatcher = sshConfigWatcher
        newTabContainer.pluginManager = pluginManager
        newTabContainer.panelRegistry = panelRegistry
        newTabContainer.aiService = aiService
        newTabContainer.skillStore = skillStore
        newTabContainer.memoryStore = memoryStore
        newTabContainer.mcpConfigStore = mcpConfigStore
        newTabContainer.eventBus = eventBus
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Simpleton"
        newWindow.tabbingMode = .preferred
        newWindow.tabbingIdentifier = "com.simpleton.terminal"
        newWindow.appearance = NSAppearance(named: .darkAqua)
        newWindow.contentViewController = newTabContainer

        newTabContainer.splitController.onPaneClose = { [weak newWindow] _ in
            newWindow?.close()
        }

        self.window?.addTabbedWindow(newWindow, ordered: .above)
        newWindow.makeKeyAndOrderFront(nil)

        // Focus the new tab's terminal
        newTabContainer.splitController.setFocus(to: newTabContainer.splitController.focusedPaneID)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Notify AppDelegate to remove this from tracked windows
        NotificationCenter.default.post(name: .simpletonWindowClosed, object: self)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let simpletonWindowClosed = Notification.Name("simpletonWindowClosed")
}
