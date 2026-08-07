// Sources/Simpleton/WindowController.swift
import AppKit
import SimpletonCore

/// Manages one window. Each window contains one or more tabs via a custom in-app `TabManager`
/// (macOS native window tabbing is disabled). The window keeps a single content-host view; the
/// active tab's `TabContainerController.view` is swapped in as that host's only subview. Each tab has
/// its own TabContainerController with its own split tree.
final class WindowController: NSWindowController, NSWindowDelegate {

    private var config: AppConfig
    private let theme: Theme

    /// The window's tabs. The first tab's container is built at init.
    let tabManager: TabManager

    /// The persistent host that always fills the window; its only subview is the active tab's view.
    private let contentHost = NSView()

    /// The child VC currently installed in the host (so we can add/remove it as a child correctly).
    private weak var installedChild: TabContainerController?

    /// The initial tab's container.
    private var tabContainer: TabContainerController

    /// Keep the window's config current so tabs opened *after* a settings change (e.g. switching to
    /// Light) inherit the new appearance instead of the config captured at window creation.
    func updateConfig(_ newConfig: AppConfig) { config = newConfig }

    /// Set these after init to propagate to all TabContainerControllers.
    var bookmarkStore: BookmarkStore? {
        didSet { forEachContainer { $0.bookmarkStore = bookmarkStore } }
    }
    var sshConfigWatcher: SSHConfigWatcher? {
        didSet { forEachContainer { $0.sshConfigWatcher = sshConfigWatcher } }
    }
    var pluginManager: PluginManager? {
        didSet { forEachContainer { $0.pluginManager = pluginManager } }
    }
    var panelRegistry: PanelRegistry? {
        didSet { forEachContainer { $0.panelRegistry = panelRegistry } }
    }
    var aiService: AIService? {
        didSet { forEachContainer { $0.aiService = aiService } }
    }
    var skillStore: SkillStore? {
        didSet { forEachContainer { $0.skillStore = skillStore } }
    }
    var memoryStore: MemoryStore? {
        didSet { forEachContainer { $0.memoryStore = memoryStore } }
    }
    var mcpConfigStore: MCPConfigStore? {
        didSet { forEachContainer { $0.mcpConfigStore = mcpConfigStore } }
    }
    var eventBus: WorkspaceEventBus? {
        didSet { forEachContainer { $0.eventBus = eventBus } }
    }

    private func forEachContainer(_ apply: (TabContainerController) -> Void) {
        for tab in tabManager.tabs { apply(tab.container) }
    }

    init(config: AppConfig, theme: Theme) {
        self.config = config
        self.theme = theme

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Simpleton"
        window.minSize = NSSize(width: 400, height: 300)
        WindowController.dissolveTitleBar(
            window, mode: config.appearance.appearanceMode,
            translucency: config.appearance.chromeTranslucency)

        let initialContainer = TabContainerController(config: config, theme: theme)
        self.tabContainer = initialContainer
        self.tabManager = TabManager(initial: initialContainer, title: window.title)

        super.init(window: window)

        // A dedicated content VC hosts the swappable tab view. The window's contentView is its view.
        let hostVC = NSViewController()
        hostVC.view = contentHost
        contentHost.autoresizingMask = [.width, .height]
        window.contentViewController = hostVC
        window.alphaValue = config.appearance.windowOpacity
        window.delegate = self

        // Give the initial container the shared tab manager so it renders the strip, then install it.
        initialContainer.tabManager = tabManager
        wireContainer(initialContainer)
        install(initialContainer)
        centerTrafficLights(in: window)

        // Manager → window: swap views on activation (and sync the title bar to the activated tab's
        // title), close window when empty, and track the active tab's live title changes.
        tabManager.onActivate = { [weak self] item in
            self?.swap(to: item.container)
            self?.window?.title = item.title
        }
        tabManager.onLastTabClosed = { [weak self] in self?.window?.close() }
        tabManager.onTitleChange = { [weak self] item in
            guard let self, item.id == self.tabManager.activeTabID else { return }
            self.window?.title = item.title
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Wire a container's split callbacks: last-pane-close closes the *tab*, and focused-pane title
    /// updates flow into the tab manager (→ strip pill + window title).
    private func wireContainer(_ container: TabContainerController) {
        container.splitController.onPaneClose = { [weak self, weak container] _ in
            guard let self, let container else { return }
            if let item = self.tabManager.tabs.first(where: { $0.container === container }) {
                self.tabManager.close(item.id)
            }
        }
        container.onTitleChange = { [weak self, weak container] title in
            guard let self, let container else { return }
            self.tabManager.setTitle(title, for: container)
        }
    }

    // MARK: - Content swapping

    /// Install a container as the host's only child + subview, full-bleed.
    ///
    /// Uses **frame-based** autoresizing (not AutoLayout pins) to attach the container's view. The
    /// container's `outer` view is an AutoLayout subtree whose header hosting-view reports a fixed
    /// intrinsic width (~474@999.9). If we pinned `outer` to the host with AutoLayout, that intrinsic
    /// width — with no concrete width flowing down from the frame-based host — becomes the binding
    /// constraint and caps how wide the window can grow. Sizing `outer` to the host's bounds and
    /// letting it autoresize gives it a concrete width (exactly as the old code attached `outer`
    /// straight to the window's content view), so the header stretches with the window. Verified via
    /// runtime layout dump: AutoLayout pin → window stuck at 474; frame-based → widens freely.
    private func install(_ container: TabContainerController) {
        if let old = installedChild {
            old.view.removeFromSuperview()
            old.removeFromParent()
        }
        contentViewController?.addChild(container)
        container.view.translatesAutoresizingMaskIntoConstraints = true
        container.view.frame = contentHost.bounds
        container.view.autoresizingMask = [.width, .height]
        contentHost.addSubview(container.view)
        installedChild = container
    }

    /// Swap the visible tab, then focus its terminal and re-center the traffic lights (AppKit resets
    /// their origin whenever the content view hierarchy changes).
    private func swap(to container: TabContainerController) {
        guard container !== installedChild else { return }
        install(container)
        centerTrafficLights(in: window)
        DispatchQueue.main.async { [weak self, weak container] in
            guard let container else { return }
            container.splitController.setFocus(to: container.splitController.focusedPaneID)
            self?.centerTrafficLights(in: self?.window)
        }
    }

    // MARK: - Chrome

    /// Dissolve the stock title bar into the app chrome (Ghostty/Warp look): apply the appearance
    /// mode, hide the title text, and make the titlebar strip transparent so it takes the window's
    /// background color. Only the traffic lights float above a continuous chrome-colored strip — no
    /// fullSize content, so the sidebar/terminal never slide under the traffic lights.
    static func dissolveTitleBar(_ window: NSWindow, mode: String, translucency: Double = 0) {
        window.appearance = AppTheme.nsAppearance(for: mode, isDark: AppTheme.activeTheme.isDark)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Chrome-colored titlebar strip — uses the active theme's chrome surface so colored themes
        // stay seamless with the sidebar (DT.surface). Neutral dark: #131316 / light: #F2F2F4.
        // When translucent, go non-opaque + clear so the chrome frost reveals the desktop.
        let translucent = translucency > 0.001
        window.isOpaque = !translucent
        window.backgroundColor = translucent
            ? .clear
            : (NSColor(hex: AppTheme.activeTheme.chrome.surface)
                ?? NSColor(srgbRed: 0.075, green: 0.075, blue: 0.086, alpha: 1))
    }

    /// The header is a 46px full-size-content strip, but AppKit positions the traffic lights for the
    /// stock ~28px titlebar, so they ride high and clip the window's top edge. Nudge the three
    /// standard buttons down so their centerline matches the header's. AppKit re-lays them out on
    /// resize / key changes, so this is re-applied from the matching delegate hooks. (Manual button
    /// repositioning against the native titlebar container is the production idiom — Chromium,
    /// INAppStoreWindow, VSCode all do this; there is no NSWindow API to grow the real titlebar.)
    static let headerHeight: CGFloat = 46
    func centerTrafficLights(in window: NSWindow?) {
        guard let window,
            let close = window.standardWindowButton(.closeButton),
            let miniaturize = window.standardWindowButton(.miniaturizeButton),
            let zoom = window.standardWindowButton(.zoomButton),
            let titlebar = close.superview
        else { return }
        let buttonHeight = close.frame.height
        // The titlebar container is not flipped (origin bottom-left) and its top edge sits flush with
        // the window's top — the same top edge the 46px header starts from. Put each button's *center*
        // on the header's centerline (headerHeight/2 below the top). In the container's coordinates the
        // origin is therefore: containerTop − headerHeight/2 − btnH/2. `round` avoids a fractional
        // origin that would blur/misalign the dots by a pixel (a known VSCode off-by-one).
        let targetY = (titlebar.bounds.height - Self.headerHeight / 2 - buttonHeight / 2).rounded()
        for button in [close, miniaturize, zoom] {
            button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: targetY))
        }
    }

    // MARK: - Public API

    /// The active split controller (for the current tab).
    var activeSplitController: SplitController {
        tabManager.activeContainer?.splitController ?? tabContainer.splitController
    }

    /// Create a new tab in this window; returns the new tab's container (used by session restore).
    /// Builds a fresh TabContainerController with the same stores as the initial one, registers it
    /// with the tab manager (which activates it and swaps the view in), and focuses its terminal.
    @discardableResult
    func newTab() -> TabContainerController {
        let newContainer = TabContainerController(config: config, theme: theme)
        newContainer.bookmarkStore = bookmarkStore
        newContainer.sshConfigWatcher = sshConfigWatcher
        newContainer.pluginManager = pluginManager
        newContainer.panelRegistry = panelRegistry
        newContainer.aiService = aiService
        newContainer.skillStore = skillStore
        newContainer.memoryStore = memoryStore
        newContainer.mcpConfigStore = mcpConfigStore
        newContainer.eventBus = eventBus
        newContainer.tabManager = tabManager

        wireContainer(newContainer)
        tabManager.add(container: newContainer)  // appends, activates, and triggers the view swap

        // Focus the new tab's terminal.
        newContainer.splitController.setFocus(to: newContainer.splitController.focusedPaneID)
        return newContainer
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Notify AppDelegate to remove this from tracked windows
        NotificationCenter.default.post(name: .simpletonWindowClosed, object: self)
    }

    // AppKit re-lays the traffic lights back to their stock position on resize and when the window
    // (re)gains key, so re-center them from these hooks to keep them aligned with the header.
    func windowDidResize(_ notification: Notification) {
        centerTrafficLights(in: notification.object as? NSWindow)
    }
    func windowDidBecomeKey(_ notification: Notification) {
        centerTrafficLights(in: notification.object as? NSWindow)
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        centerTrafficLights(in: notification.object as? NSWindow)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let simpletonWindowClosed = Notification.Name("simpletonWindowClosed")
}

// MARK: - Window → active container resolution

extension NSWindow {
    /// The WindowController that owns this window (it is set as the window's delegate at init).
    var simpletonWindowController: WindowController? { delegate as? WindowController }

    /// The active tab's container for this window, if it is a Simpleton terminal window. Replaces the
    /// old `contentViewController as? TabContainerController` (which no longer holds — the window's
    /// content VC is now a swappable host, not the container itself).
    var activeTabContainer: TabContainerController? {
        simpletonWindowController?.tabManager.activeContainer
    }
}
