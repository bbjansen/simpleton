// Sources/Simpleton/WindowController.swift
import AppKit
import SimpletonCore

/// Manages one window. Each window contains one or more tabs (via native AppKit tabbing).
/// Each tab has its own TabContainerController with its own split tree.
final class WindowController: NSWindowController, NSWindowDelegate {

    private var config: AppConfig
    private let theme: Theme
    private var tabContainer: TabContainerController

    /// Keep the window's config current so tabs opened *after* a settings change (e.g. switching to
    /// Light) inherit the new appearance instead of the config captured at window creation.
    func updateConfig(_ newConfig: AppConfig) { config = newConfig }

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
        WindowController.dissolveTitleBar(window, mode: config.appearance.appearanceMode)

        self.tabContainer = TabContainerController(config: config, theme: theme)

        super.init(window: window)

        window.contentViewController = tabContainer
        window.alphaValue = config.appearance.windowOpacity
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

    // MARK: - Chrome

    /// Dissolve the stock title bar into the app chrome (Ghostty/Warp look): apply the appearance
    /// mode, hide the title text, and make the titlebar strip transparent so it takes the window's
    /// background color. Only the traffic lights float above a continuous chrome-colored strip — no
    /// fullSize content, so the sidebar/terminal never slide under the traffic lights.
    static func dissolveTitleBar(_ window: NSWindow, mode: String) {
        window.appearance = AppTheme.nsAppearance(for: mode)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Chrome-colored titlebar strip that follows light/dark. Dark #131316 / Light #F2F2F4;
        // frames the terminal well below it (chrome lighter/darker than content, per Zed).
        window.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(srgbRed: 0.075, green: 0.075, blue: 0.086, alpha: 1)
                : NSColor(srgbRed: 0.949, green: 0.949, blue: 0.957, alpha: 1)
        }
    }

    // MARK: - Public API

    /// The active split controller (for the current tab).
    var activeSplitController: SplitController {
        tabContainer.splitController
    }

    /// Create a new tab in this window; returns the new tab's container (used by session restore).
    @discardableResult
    func newTab() -> TabContainerController {
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
        WindowController.dissolveTitleBar(newWindow, mode: config.appearance.appearanceMode)
        newWindow.contentViewController = newTabContainer
        newWindow.alphaValue = config.appearance.windowOpacity

        newTabContainer.splitController.onPaneClose = { [weak newWindow] _ in
            newWindow?.close()
        }

        self.window?.addTabbedWindow(newWindow, ordered: .above)
        newWindow.makeKeyAndOrderFront(nil)

        // Focus the new tab's terminal
        newTabContainer.splitController.setFocus(to: newTabContainer.splitController.focusedPaneID)
        return newTabContainer
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
