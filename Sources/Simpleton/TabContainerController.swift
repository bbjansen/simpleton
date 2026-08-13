// Sources/Simpleton/TabContainerController.swift
import AppKit
import Combine
import SimpletonCore
import SwiftUI

/// View controller for one tab's content. Owns a SplitController and manages
/// creating new panes when splits are requested.
final class TabContainerController: NSViewController {

    let splitController: SplitController
    private var config: AppConfig
    private let theme: Theme
    private var closeObserver: NSObjectProtocol?
    private var searchObserver: NSObjectProtocol?
    // Notification shims — kept so existing menu items continue to work
    private var sidebarShimObserver: NSObjectProtocol?
    private var aiChatShimObserver: NSObjectProtocol?
    private var skillPickerShimObserver: NSObjectProtocol?
    private var openConnectionObserver: NSObjectProtocol?
    private var openConnectionTextObserver: NSObjectProtocol?

    // Auto Layout panel management
    private var contentSplit: NSSplitView?
    /// Outer split stacking [contentSplit, drawer?] so a GUI client can dock on an edge.
    private var outerSplit: NSSplitView?
    private var drawerPanelVC: NSViewController?
    private var drawerPanelID: String?
    private var leftBarHost: NSHostingView<ActivityBarView>?
    private var rightBarHost: NSHostingView<ActivityBarView>?
    /// The right activity bar's width constraint, kept so it can collapse to 0 when that side has
    /// no panels (e.g. after the AI panel became a header-only button).
    private var rightBarWidthConstraint: NSLayoutConstraint?
    private var headerHost: NSHostingView<HeaderBarView>?
    private var tabStripHost: NSHostingView<TabStripView>?
    private let headerModel = HeaderModel()
    /// The content area (backdrop + tint + split + activity bars) that sits *below* the header.
    private var contentContainer: NSView?
    private var outerView: NSView?
    /// Pins the content's top to the tab strip's bottom (or the header's bottom when no strip yet).
    private var containerTopConstraint: NSLayoutConstraint?

    /// The window's shared tab manager (in-app tabbing). Set by WindowController right after init and
    /// before the view is installed. Every tab's container renders the strip from this same manager,
    /// so the strip looks continuous as the active container swaps.
    var tabManager: TabManager? {
        didSet {
            if isViewLoaded { installTabStripIfNeeded() }
        }
    }

    /// Called when this tab's focused pane changes its title, so the WindowController can update the
    /// shared tab manager (→ strip pill + window title). Set by WindowController.
    var onTitleChange: ((String) -> Void)?

    /// Drives the tab-strip band height: 0 with a single tab (strip hidden, Terminal.app style),
    /// TabStripView.height with two or more. Toggled by observing the manager's tab count.
    private var tabStripHeightConstraint: NSLayoutConstraint?
    private var tabCountCancellable: AnyCancellable?
    private var backdropTint: NSView?
    /// Gradient wash layer for gradient themes, hosted in `backdropTint`. Nil / detached for solid
    /// themes (which fall back to a flat `layer.backgroundColor`). Sized to the tint view each pass.
    private var backdropGradientLayer: CAGradientLayer?
    private var leftPanelVC: NSViewController?
    private var leftPanelID: String?
    private var rightPanelVC: NSViewController?
    private var rightPanelID: String?
    private var cancellables = Set<AnyCancellable>()

    /// Per-tab AI conversation. Created lazily when aiService is available.
    private(set) var tabConversation: TabConversation?

    /// Set before the window is shown. Propagated from AppDelegate → WindowController → here.
    var panelRegistry: PanelRegistry? {
        didSet {
            subscribeToRegistry()
            if isViewLoaded {
                rebuildActivityBars()
                installHeaderIfNeeded()
            }
        }
    }

    /// Lightweight project indexer — shared across AI chat messages for caching.
    private let projectIndexer = ProjectIndexer()

    /// Set from WindowController after init.
    var bookmarkStore: BookmarkStore?
    var sshConfigWatcher: SSHConfigWatcher?
    var pluginManager: PluginManager?
    var skillStore: SkillStore?
    var memoryStore: MemoryStore?
    var mcpConfigStore: MCPConfigStore?
    var eventBus: WorkspaceEventBus?
    var aiService: AIService? {
        didSet {
            if tabConversation == nil, let aiService = aiService {
                tabConversation = TabConversation(
                    tabID: UUID(),
                    splitController: splitController,
                    aiService: aiService
                )
                panelRegistry?.rebindAIChat(to: tabConversation)
            }
            // Propagate to all existing panes so active AI hints work.
            for pane in splitController.panes.values {
                pane.aiService = aiService
            }
        }
    }

    private var appSupportDir: URL { AppPaths.appSupport }

    init(config: AppConfig, theme: Theme) {
        self.config = config
        self.theme = theme

        let shell = ShellDetector.detectShell(config: config)
        let workingDir = ShellDetector.workingDirectory(config: config)
        let initialPane = PaneController(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            connectionType: .local(shell: shell, workingDirectory: workingDir)
        )
        ThemeApplier.apply(theme: theme, config: config, to: initialPane.terminalView)
        self.splitController = SplitController(initialPaneController: initialPane)
        super.init(nibName: nil, bundle: nil)

        splitController.paneFactory = { [weak self] paneID in
            guard let self else {
                return PaneController(
                    id: paneID, frame: .zero,
                    connectionType: .local(shell: "/bin/zsh", workingDirectory: NSHomeDirectory())
                )
            }
            let focusedCWD = self.splitController.panes[self.splitController.focusedPaneID]?.currentDirectory
            return self.createPane(id: paneID, inheritedWorkingDirectory: focusedCWD)
        }

        closeObserver = NotificationCenter.default.addObserver(
            forName: .simpletonPaneCloseRequested, object: nil, queue: .main
        ) { [weak self] notification in
            guard let paneID = notification.object as? PaneID,
                let self = self,
                self.splitController.panes[paneID] != nil
            else { return }
            self.splitController.closePane(paneID)
        }

        searchObserver = NotificationCenter.default.addObserver(
            forName: .simpletonShowSearch, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self,
                let pane = self.splitController.panes[self.splitController.focusedPaneID]
            else { return }
            pane.showSearch()
        }

        // Shim: sidebar toggle → toggle connections panel on left
        sidebarShimObserver = NotificationCenter.default.addObserver(
            forName: .simpletonToggleSidebar, object: nil, queue: .main
        ) { [weak self] _ in
            guard let registry = self?.panelRegistry else { return }
            var profile = registry.activeProfile
            profile.togglePanel(id: PanelProfile.PanelID.connections, on: .left)
            registry.activeProfile = profile
        }

        // Shim: AI chat toggle → toggle ai-chat panel on right
        aiChatShimObserver = NotificationCenter.default.addObserver(
            forName: .simpletonToggleAIChat, object: nil, queue: .main
        ) { [weak self] _ in
            guard let registry = self?.panelRegistry else { return }
            var profile = registry.activeProfile
            profile.togglePanel(id: PanelProfile.PanelID.aiChat, on: .right)
            registry.activeProfile = profile
        }

        // Shim: skill picker → open skills panel on right
        openConnectionObserver = NotificationCenter.default.addObserver(
            forName: .simpletonOpenConnectionGUI, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self,
                let registry = self.panelRegistry,
                self.view.window?.isKeyWindow == true
            else { return }
            // If SQL is already the active right panel, the mounted panel's own `.onReceive` consumes
            // the pending connection — skip the profile re-assignment (which would needlessly rebuild
            // panels across every container that shares this registry).
            guard registry.activeProfile.rightActivePanelID != PanelProfile.PanelID.sql else { return }
            var profile = registry.activeProfile
            profile.activatePanel(id: PanelProfile.PanelID.sql, on: .right)
            registry.activeProfile = profile
        }

        openConnectionTextObserver = NotificationCenter.default.addObserver(
            forName: .simpletonOpenConnectionText, object: nil, queue: .main
        ) { [weak self] note in
            guard let self = self, self.view.window?.isKeyWindow == true,
                let id = note.object as? UUID
            else { return }
            let dir = self.appSupportDir
            Task { [weak self] in
                let store = ConnectionStore(directory: dir)
                guard let connection = await store.connection(for: id) else { return }
                let secret = CredentialStore.secret(for: id)
                await MainActor.run {
                    self?.openClientPane(connection: connection, secret: secret, direction: .vertical)
                }
            }
        }

        skillPickerShimObserver = NotificationCenter.default.addObserver(
            forName: .simpletonRunSkillPicker, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self = self,
                let registry = self.panelRegistry,
                self.view.window?.isKeyWindow == true
            else { return }
            // Update aiService if passed via notification (legacy path)
            if let svc = notification.object as? AIService { self.aiService = svc }
            var profile = registry.activeProfile
            profile.activatePanel(id: PanelProfile.PanelID.skills, on: .right)
            registry.activeProfile = profile
            // Notify skills panel to focus the search field
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                NotificationCenter.default.post(name: .simpletonActivateSkillPicker, object: nil)
            }
        }

        initialPane.onFocused = { [weak self] focusedPane in
            self?.splitController.setFocus(to: focusedPane.id)
        }
        initialPane.onTitleChange = { [weak self] title in
            self?.onTitleChange?(title)
        }

        let env = buildEnvironment()
        initialPane.startLocalShell(
            shell: shell, args: shellLaunchArgs(for: shell), environment: env, workingDirectory: workingDir)

        // Wire split tree changes to pane label rebuilds
        splitController.onTreeChange = { [weak self] in
            self?.tabConversation?.rebuildPaneLabels()
        }

        DispatchQueue.main.async { [weak self] in
            self?.pluginManager?.fireEvent(
                .onTabOpen,
                context: [
                    "tabId": UUID().uuidString,
                    "windowId": self?.view.window?.windowNumber ?? 0,
                ])
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        [
            closeObserver, searchObserver, sidebarShimObserver,
            aiChatShimObserver, skillPickerShimObserver, openConnectionObserver,
            openConnectionTextObserver,
        ].forEach {
            if let obs = $0 { NotificationCenter.default.removeObserver(obs) }
        }
    }

    override func loadView() {
        let frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let container = NSView(frame: frame)
        container.autoresizingMask = [.width, .height]

        // Subtle within-window vibrancy backdrop behind the chrome. The window stays opaque (so no
        // view can leak the desktop and lose text contrast); the frosted Material on the rails and
        // sidebar reads over this for a soft, legible native feel.
        let backdrop = NSVisualEffectView.backdrop(material: .underWindowBackground)
        backdrop.blendingMode = .withinWindow
        container.addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: container.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // Theme-color wash over the backdrop so transparent chrome — the side panels and any gaps —
        // reads as the active theme's color instead of neutral vibrancy. Sits behind the split, so it
        // never intercepts events. Refreshed on a live theme change via updateConfig.
        let tint = BackdropTintView()
        tint.wantsLayer = true
        tint.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tint)
        NSLayoutConstraint.activate([
            tint.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tint.topAnchor.constraint(equalTo: container.topAnchor),
            tint.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        self.backdropTint = tint
        applyBackdropTint()

        // Central NSSplitView: [leftPanel?] | terminal | [rightPanel?]
        let split = NSSplitView(frame: frame)
        split.isVertical = true
        split.dividerStyle = .thin
        contentSplit = split

        // Terminal is always the first arranged subview in contentSplit
        splitController.rootView.frame = frame
        split.addArrangedSubview(splitController.rootView)

        // Outer split stacks the content split (top) above an optional edge drawer (bottom),
        // via a horizontal divider. contentSplit becomes its first arranged subview.
        let outerSplitView = NSSplitView(frame: frame)
        outerSplitView.isVertical = false
        outerSplitView.dividerStyle = .thin
        outerSplitView.translatesAutoresizingMaskIntoConstraints = false
        outerSplitView.addArrangedSubview(split)
        container.addSubview(outerSplitView)
        outerSplit = outerSplitView

        if let registry = panelRegistry {
            mountActivityBars(in: container, registry: registry)
        } else {
            // Fallback: no activity bars — content fills the full width
            NSLayoutConstraint.activate([
                outerSplitView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                outerSplitView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                outerSplitView.topAnchor.constraint(equalTo: container.topAnchor),
                outerSplitView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }

        // Wrap the content in an outer view with the Slack-style header on top. The inner `container`
        // (backdrop + tint + split + activity bars) is pinned *below* the header, so all the layout
        // above is unchanged — it simply starts under the header strip.
        contentContainer = container
        container.translatesAutoresizingMaskIntoConstraints = false

        let outer = NSView(frame: frame)
        outer.autoresizingMask = [.width, .height]
        outer.addSubview(container)
        outerView = outer

        // Pin the content to the top for now. `installHeaderIfNeeded()` swaps this to `header.bottom`
        // once the panel registry arrives (it's assigned after the view loads).
        let topC = container.topAnchor.constraint(equalTo: outer.topAnchor)
        containerTopConstraint = topC
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: outer.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: outer.trailingAnchor),
            topC,
            container.bottomAnchor.constraint(equalTo: outer.bottomAnchor),
        ])

        self.view = outer
        installHeaderIfNeeded()
        installTabStripIfNeeded()
    }

    /// Build and pin the Slack-style header above the content. Idempotent; needs the panel registry
    /// (for the workspace switcher), which is assigned after `loadView`, so this is also called from
    /// the `panelRegistry` didSet.
    private func installHeaderIfNeeded() {
        guard headerHost == nil, let outer = outerView, let registry = panelRegistry
        else { return }
        let header = NSHostingView(rootView: HeaderBarView(registry: registry, model: headerModel))
        header.translatesAutoresizingMaskIntoConstraints = false
        // The header is pinned to the window's top, which overlaps the transparent title-bar strip.
        // By default an NSHostingView insets its SwiftUI content by the window's top safe-area (the
        // title-bar height), so the header's themed background stops ~title-bar-height below the top
        // and the desktop shows through that sliver above the traffic lights. Clearing safeAreaRegions
        // lets the themed surface fill the full 46px frame, right up to the window's top edge.
        header.safeAreaRegions = []
        // The header's SwiftUI content has a fixed *ideal* width (~474). Left to drive AutoLayout,
        // that intrinsic width becomes a required constraint that AppKit clamps the whole window to
        // (window stuck at 474 — verified via runtime `setContentSize` probe). The header is chrome
        // that must stretch, and its width is already fully determined by the leading/trailing pins to
        // `outer`, so stop it from reporting an intrinsic size at all.
        header.sizingOptions = []
        outer.addSubview(header)
        headerHost = header
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: outer.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: outer.trailingAnchor),
            header.topAnchor.constraint(equalTo: outer.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 46),
        ])
        installTabStripIfNeeded()
        relinkContentTop()
    }

    /// Build and pin the custom in-app tab strip directly below the header. Idempotent; needs the
    /// header (so it can pin under it) and the shared tab manager (assigned by WindowController), so
    /// this is also invoked when either becomes available. The SwiftUI strip hides itself at 1 tab.
    private func installTabStripIfNeeded() {
        guard tabStripHost == nil, let outer = outerView,
            let header = headerHost, let manager = tabManager
        else { return }
        let strip = NSHostingView(rootView: TabStripView(manager: manager))
        strip.translatesAutoresizingMaskIntoConstraints = false
        strip.safeAreaRegions = []
        // Same reasoning as the header: don't let the strip's SwiftUI content drive AutoLayout width
        // (it would clamp the window). Width comes from the leading/trailing pins; height is an
        // explicit constraint we toggle by tab count (0 hidden / TabStripView.height shown).
        strip.sizingOptions = []
        outer.addSubview(strip)
        tabStripHost = strip
        let heightC = strip.heightAnchor.constraint(
            equalToConstant: manager.tabs.count > 1 ? TabStripView.height : 0)
        tabStripHeightConstraint = heightC
        NSLayoutConstraint.activate([
            strip.leadingAnchor.constraint(equalTo: outer.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: outer.trailingAnchor),
            strip.topAnchor.constraint(equalTo: header.bottomAnchor),
            heightC,
        ])
        // Collapse/expand the band as tabs are added/removed (published on every tab-list change).
        tabCountCancellable = manager.$tabs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tabs in
                self?.tabStripHeightConstraint?.constant = tabs.count > 1 ? TabStripView.height : 0
            }
        relinkContentTop()
    }

    /// Re-pin the content's top edge to whatever chrome sits above it: the tab strip if present, else
    /// the header if present, else the outer's top. Keeps the layout chain correct as chrome arrives.
    private func relinkContentTop() {
        guard let outer = outerView, let container = contentContainer else { return }
        containerTopConstraint?.isActive = false
        let anchor: NSLayoutYAxisAnchor
        if let strip = tabStripHost {
            anchor = strip.bottomAnchor
        } else if let header = headerHost {
            anchor = header.bottomAnchor
        } else {
            anchor = outer.topAnchor
        }
        let newTop = container.topAnchor.constraint(equalTo: anchor)
        containerTopConstraint = newTop
        newTop.isActive = true
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        splitController.setFocus(to: splitController.focusedPaneID)
        // Rebind AI Chat panel to this tab's conversation
        panelRegistry?.rebindAIChat(to: tabConversation)
    }

    /// Ensure the split's current root view is mounted in `contentSplit` at index 0 (the terminal
    /// slot, before any panels). Session restore replaces the split tree via `SplitController.restore`,
    /// whose `reconcile()` only re-parents the rebuilt root view if it still has a superview; when a
    /// tab's container isn't mounted in the window at restore time, that superview is nil and the new
    /// terminal ends up orphaned (blank pane). Calling this after a restore re-inserts it so the
    /// restored terminals actually render. No-op when it's already in place (fresh tabs).
    func reinstallSplitRootIfNeeded() {
        guard let split = contentSplit else { return }
        let root = splitController.rootView
        if root.superview === split { return }
        root.removeFromSuperview()
        root.frame = split.bounds
        root.autoresizingMask = [.width, .height]
        split.insertArrangedSubview(root, at: 0)
        split.adjustSubviews()
    }

    // MARK: - Activity Bars

    private func mountActivityBars(in container: NSView, registry: PanelRegistry) {
        guard let outer = outerSplit else { return }

        let leftBar = NSHostingView(
            rootView: ActivityBarView(
                side: .left,
                registry: registry,
                onOpenSettings: {
                    NotificationCenter.default.post(name: .simpletonShowPreferences, object: nil)
                }
            ))
        leftBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(leftBar)
        leftBarHost = leftBar

        let rightBar = NSHostingView(
            rootView: ActivityBarView(
                side: .right,
                registry: registry,
                onOpenSettings: nil
            ))
        rightBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(rightBar)
        rightBarHost = rightBar

        let rightWidth = rightBar.widthAnchor.constraint(equalToConstant: 40)
        rightBarWidthConstraint = rightWidth

        NSLayoutConstraint.activate([
            // Left bar
            leftBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            leftBar.topAnchor.constraint(equalTo: container.topAnchor),
            leftBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            leftBar.widthAnchor.constraint(equalToConstant: 40),
            // Right bar
            rightBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rightBar.topAnchor.constraint(equalTo: container.topAnchor),
            rightBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            rightWidth,
            // Content (outer split) between bars
            outer.leadingAnchor.constraint(equalTo: leftBar.trailingAnchor),
            outer.trailingAnchor.constraint(equalTo: rightBar.leadingAnchor),
            outer.topAnchor.constraint(equalTo: container.topAnchor),
            outer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        updateRightBarVisibility(for: registry.activeProfile)
    }

    /// Collapse the right activity-bar rail to zero width and hide it when its side has no panels
    /// (e.g. after the AI panel moved to a header-only button). It reappears automatically once a
    /// right-side panel is added to the profile.
    private func updateRightBarVisibility(for profile: PanelProfile) {
        let show = config.appearance.showToolLauncher && !profile.rightPanelIDs.isEmpty
        rightBarWidthConstraint?.constant = show ? 40 : 0
        rightBarHost?.isHidden = !show
    }

    private func rebuildActivityBars() {
        guard let registry = panelRegistry, let container = contentContainer else { return }
        leftBarHost?.removeFromSuperview()
        rightBarHost?.removeFromSuperview()
        leftBarHost = nil
        rightBarHost = nil

        // Remove old outer-split-to-container constraints before remounting
        if let outer = outerSplit {
            let old = container.constraints.filter {
                ($0.firstItem as? NSView == outer || $0.secondItem as? NSView == outer)
                    && ($0.firstItem as? NSView == container || $0.secondItem as? NSView == container)
            }
            NSLayoutConstraint.deactivate(old)
        }
        mountActivityBars(in: container, registry: registry)
    }

    // MARK: - Combine Subscription

    private func subscribeToRegistry() {
        cancellables.removeAll()
        guard let registry = panelRegistry else { return }
        registry.$activeProfile
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profile in
                self?.updatePanels(for: profile)
            }
            .store(in: &cancellables)
    }

    // MARK: - Panel Show/Hide

    private func updatePanels(for profile: PanelProfile) {
        guard let split = contentSplit else { return }

        updateRightBarVisibility(for: profile)

        // ── 1. Tear down any existing panel VCs ────────────────
        if let vc = leftPanelVC {
            vc.view.removeFromSuperview()
            vc.removeFromParent()
            leftPanelVC = nil
            leftPanelID = nil
        }
        if let vc = rightPanelVC {
            vc.view.removeFromSuperview()
            vc.removeFromParent()
            rightPanelVC = nil
            rightPanelID = nil
        }

        // After teardown, split.arrangedSubviews == [terminal rootView]

        // ── 2. Insert left panel at index 0 (before terminal) ──
        if let id = profile.leftActivePanelID,
            let vc = panelRegistry?.makeController(for: id, context: makeContext())
        {
            addChild(vc)
            vc.view.frame = NSRect(x: 0, y: 0, width: profile.leftWidth, height: split.bounds.height)
            split.insertArrangedSubview(vc.view, at: 0)
            leftPanelVC = vc
            leftPanelID = id
        }

        // ── 3. Append right panel at end (after terminal) ──────
        if let id = profile.rightActivePanelID,
            let vc = panelRegistry?.makeController(for: id, context: makeContext())
        {
            addChild(vc)
            vc.view.frame = NSRect(x: 0, y: 0, width: profile.rightWidth, height: split.bounds.height)
            split.addArrangedSubview(vc.view)
            rightPanelVC = vc
            rightPanelID = id
        }

        // ── 3b. Drawer (edge-docked GUI client) ────────────────
        if let vc = drawerPanelVC {
            vc.view.removeFromSuperview()
            vc.removeFromParent()
            drawerPanelVC = nil
            drawerPanelID = nil
        }
        if let id = profile.bottomActivePanelID,
            let outer = outerSplit,
            let vc = panelRegistry?.makeController(for: id, context: makeContext())
        {
            addChild(vc)
            vc.view.frame = NSRect(x: 0, y: 0, width: outer.bounds.width, height: profile.drawerSize)
            if profile.drawerEdge == .top {
                outer.insertArrangedSubview(vc.view, at: 0)
            } else {
                outer.addArrangedSubview(vc.view)  // .bottom (and .trailing treated as bottom for v1)
            }
            drawerPanelVC = vc
            drawerPanelID = id
        }

        // ── 4. Set divider positions ───────────────────────────
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let split = self.contentSplit else { return }
            var dividerIdx = 0
            if self.leftPanelVC != nil {
                split.setPosition(profile.leftWidth, ofDividerAt: dividerIdx)
                dividerIdx += 1
            }
            if self.rightPanelVC != nil {
                let rightPos = split.bounds.width - profile.rightWidth
                split.setPosition(rightPos, ofDividerAt: dividerIdx)
            }
            if let outer = self.outerSplit, self.drawerPanelVC != nil {
                let pos =
                    profile.drawerEdge == .top
                    ? profile.drawerSize
                    : outer.bounds.height - profile.drawerSize
                outer.setPosition(pos, ofDividerAt: 0)
            }
            self.splitController.setFocus(to: self.splitController.focusedPaneID)
        }
    }

    /// Open (or close, with nil) the edge drawer's GUI panel.
    func activateDrawer(id: String?) {
        guard let registry = panelRegistry else { return }
        var profile = registry.activeProfile
        profile.setDrawer(id: id)
        registry.activeProfile = profile
    }

    // MARK: - Context

    /// The container that panel actions should target. Panels are cached and shared across
    /// all tabs by PanelRegistry, so a panel created for the first tab is reused in every
    /// tab. Resolve the ACTIVE tab (the key window's container) at call time so sidebar
    /// actions — opening an SSH host, inserting a command — target the tab the user is on
    /// rather than always the first tab. Falls back to this container.
    private var activePanelContainer: TabContainerController {
        NSApp.keyWindow?.activeTabContainer ?? self
    }

    /// Push a fresh app config into this container so cached panels — which read
    /// `appConfig()` lazily — observe changes made in Preferences.
    func updateConfig(_ newConfig: AppConfig) {
        self.config = newConfig
        applyBackdropTint()  // retint the side-panel backdrop on a live theme change
        if let registry = panelRegistry {
            updateRightBarVisibility(for: registry.activeProfile)  // live-toggle the launcher rail
        }
    }

    /// Paint the backdrop with the active theme so transparent side panels read as the theme. For a
    /// gradient theme this lays down the SAME diagonal two-hue blend the SwiftUI chrome uses (via
    /// `themedGlass`), so there is no flat-vs-gradient seam where the tint peeks out from behind the
    /// header/rails at translucency; for a solid theme it stays a flat surface fill.
    private func applyBackdropTint() {
        guard let tint = backdropTint, let layer = tint.layer else { return }
        // Fade the theme-color wash as translucency rises so the desktop shows through the frost.
        let alpha = 0.85 - min(max(config.appearance.chromeTranslucency, 0), 0.6)

        if let stops = AppTheme.activeTheme.gradient,
            stops.count >= 2,
            case let cgColors = stops.compactMap({ NSColor(hex: $0)?.withAlphaComponent(alpha).cgColor }),
            cgColors.count >= 2
        {
            // Gradient theme: host a CAGradientLayer that mirrors the SwiftUI blend
            // (LinearGradient .topLeading → .bottomTrailing). In the tint view's non-flipped layer
            // geometry (0,0 = bottom-left) that is start (0,1) top-leading → end (1,0) bottom-trailing.
            // The BackdropTintView keeps this sublayer sized to bounds in its `layout()`.
            let grad = backdropGradientLayer ?? CAGradientLayer()
            grad.colors = cgColors
            grad.startPoint = CGPoint(x: 0, y: 1)
            grad.endPoint = CGPoint(x: 1, y: 0)
            grad.frame = layer.bounds
            if grad.superlayer == nil { layer.addSublayer(grad) }
            (tint as? BackdropTintView)?.gradientLayer = grad
            backdropGradientLayer = grad
            layer.backgroundColor = nil  // gradient supplies the fill
        } else {
            // Solid theme: flat surface fill, and drop any gradient layer left from a prior theme.
            backdropGradientLayer?.removeFromSuperlayer()
            backdropGradientLayer = nil
            (tint as? BackdropTintView)?.gradientLayer = nil
            layer.backgroundColor =
                NSColor(hex: AppTheme.activeTheme.chrome.surface)?.withAlphaComponent(alpha).cgColor
        }
    }

    private func makeContext() -> PanelContext {
        PanelContext(
            tabContainer: { [weak self] in self?.activePanelContainer },
            skillStore: skillStore,
            memoryStore: memoryStore,
            mcpConfigStore: mcpConfigStore,
            eventBus: eventBus,
            projectIndexer: projectIndexer,
            bookmarkStore: bookmarkStore,
            aiService: aiService,
            sshConfigWatcher: sshConfigWatcher,
            appConfig: { [weak self] in self?.config ?? AppConfig() },
            currentPane: { [weak self] in
                guard let tc = self?.activePanelContainer else { return nil }
                return tc.splitController.panes[tc.splitController.focusedPaneID]
            },
            onInsertCommand: { [weak self] cmd in
                guard let tc = self?.activePanelContainer,
                    let pane = tc.splitController.panes[tc.splitController.focusedPaneID]
                else { return }
                let bytes = Array(cmd.utf8)
                pane.terminalView.send(data: bytes[...])
            },
            appSupportDir: appSupportDir
        )
    }

    // MARK: - Pane Factory

    private func createPane(id: PaneID, inheritedWorkingDirectory: String? = nil) -> PaneController {
        let shell = ShellDetector.detectShell(config: config)
        let workingDir = inheritedWorkingDirectory ?? ShellDetector.workingDirectory(config: config)
        let pane = PaneController(
            id: id,
            frame: NSRect(x: 0, y: 0, width: 400, height: 300),
            connectionType: .local(shell: shell, workingDirectory: workingDir)
        )
        pane.pluginManager = pluginManager
        pane.aiService = aiService
        pane.eventBus = eventBus
        pane.eventBusTabID = tabConversation?.tabID
        pane.paneLabel = tabConversation?.paneLabels[id] ?? "Pane"
        ThemeApplier.apply(theme: theme, config: config, to: pane.terminalView)
        let env = buildEnvironment()
        pane.startLocalShell(
            shell: shell, args: shellLaunchArgs(for: shell), environment: env, workingDirectory: workingDir)
        pane.onTitleChange = { [weak self] title in
            guard let self else { return }
            pane.paneLabel = self.tabConversation?.paneLabels[pane.id] ?? title
            // Only the focused pane drives the tab/window title.
            if self.splitController.focusedPaneID == pane.id { self.onTitleChange?(title) }
        }
        pane.onFocused = { [weak self] focusedPane in
            self?.splitController.setFocus(to: focusedPane.id)
        }
        return pane
    }

    private func buildEnvironment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = config.general.termVariable
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        // Opt-in OSC 133 shell integration (zsh): point ZDOTDIR at our integration dir, which
        // restores the user's real ZDOTDIR first so their startup files still load untouched.
        if config.general.shellIntegration, ShellIntegration.isZsh(ShellDetector.detectShell(config: config)) {
            if let userZDotDir = env["ZDOTDIR"] { env["SIMPLETON_USER_ZDOTDIR"] = userZDotDir }
            env["ZDOTDIR"] = AppPaths.shellIntegrationDir.path
        }
        return env.map { "\($0.key)=\($0.value)" }
    }

    /// Shell launch args, accounting for opt-in bash integration (which needs --rcfile).
    private func shellLaunchArgs(for shell: String) -> [String] {
        ShellIntegration.launchArgs(
            shellPath: shell,
            integrationEnabled: config.general.shellIntegration,
            bashRcfilePath: AppPaths.shellIntegrationDir.appendingPathComponent("bash-rcfile").path
        )
    }

    // MARK: - Text (CLI) Clients

    /// Open a data connection as a text client in a new split pane running its CLI.
    func openClientPane(connection: Connection, secret: ConnectionSecret?, direction: SplitDirection) {
        let previousFactory = splitController.paneFactory
        splitController.paneFactory = { [weak self] paneID in
            guard let self = self else {
                return PaneController(
                    id: paneID, frame: .zero,
                    connectionType: .local(shell: "/bin/zsh", workingDirectory: NSHomeDirectory()))
            }
            let cwd = self.splitController.panes[self.splitController.focusedPaneID]?.currentDirectory
            let pane = self.createPane(id: paneID, inheritedWorkingDirectory: cwd)
            pane.startClient(connection: connection, secret: secret)
            return pane
        }
        splitController.splitFocusedPane(direction: direction)
        splitController.paneFactory = previousFactory
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.splitController.setFocus(to: self.splitController.focusedPaneID)
        }
    }

    // MARK: - SSH Connections

    func openSSHConnection(bookmark: Bookmark, inNewSplit direction: SplitDirection? = nil) {
        if let direction = direction {
            let previousFactory = splitController.paneFactory
            splitController.paneFactory = { [weak self] paneID in
                guard let self = self else {
                    return PaneController(id: paneID, frame: .zero, connectionType: .ssh(bookmarkID: bookmark.id))
                }
                return self.createSSHPane(id: paneID, bookmark: bookmark)
            }
            splitController.splitFocusedPane(direction: direction)
            splitController.paneFactory = previousFactory
        } else {
            if let pane = splitController.panes[splitController.focusedPaneID] {
                pane.startSSH(bookmark: bookmark, config: config)
            }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.splitController.setFocus(to: self.splitController.focusedPaneID)
        }
        Task { await bookmarkStore?.recordUse(bookmarkId: bookmark.id) }
    }

    // MARK: - Command panes (TUI plugins)

    /// Open a new split pane running the user's shell, then run `command` in it (e.g. a TUI like
    /// lazygit). The command runs in the real shell so PATH/aliases resolve, and the pane drops
    /// back to a prompt when the TUI exits.
    func openCommandPane(command: String, direction: SplitDirection) {
        let previousFactory = splitController.paneFactory
        splitController.paneFactory = { [weak self] paneID in
            guard let self = self else {
                return PaneController(
                    id: paneID, frame: .zero,
                    connectionType: .local(shell: "/bin/zsh", workingDirectory: NSHomeDirectory()))
            }
            let cwd = self.splitController.panes[self.splitController.focusedPaneID]?.currentDirectory
            let pane = self.createPane(id: paneID, inheritedWorkingDirectory: cwd)
            self.runCommand(command, in: pane)
            return pane
        }
        splitController.splitFocusedPane(direction: direction)
        splitController.paneFactory = previousFactory
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.splitController.setFocus(to: self.splitController.focusedPaneID)
        }
    }

    /// Run `command` in the focused pane's shell (used for the initial pane of a new tab).
    func runCommandInFocusedPane(_ command: String) {
        guard let pane = splitController.panes[splitController.focusedPaneID] else { return }
        runCommand(command, in: pane)
    }

    private func runCommand(_ command: String, in pane: PaneController) {
        // Give the freshly-started shell a moment before feeding it the command.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak pane] in
            guard let pane = pane else { return }
            pane.terminalView.send(data: Array((command + "\n").utf8)[...])
        }
    }

    private func createSSHPane(id: PaneID, bookmark: Bookmark) -> PaneController {
        let pane = PaneController(
            id: id, frame: NSRect(x: 0, y: 0, width: 400, height: 300),
            connectionType: .ssh(bookmarkID: bookmark.id)
        )
        pane.pluginManager = pluginManager
        pane.aiService = aiService
        pane.eventBus = eventBus
        pane.eventBusTabID = tabConversation?.tabID
        pane.paneLabel = tabConversation?.paneLabels[id] ?? "Pane"
        ThemeApplier.apply(theme: theme, config: config, to: pane.terminalView)
        pane.startSSH(bookmark: bookmark, config: config)
        pane.onTitleChange = { [weak self] title in
            guard let self else { return }
            pane.paneLabel = self.tabConversation?.paneLabels[pane.id] ?? title
            if self.splitController.focusedPaneID == pane.id { self.onTitleChange?(title) }
        }
        pane.onFocused = { [weak self] focusedPane in
            self?.splitController.setFocus(to: focusedPane.id)
        }
        return pane
    }
}

/// The full-bleed theme-color wash behind the chrome vibrancy. A plain layer-backed NSView, except it
/// keeps an optional gradient sublayer (installed by `applyBackdropTint` for gradient themes) sized to
/// its bounds — CALayer sublayers don't autoresize with a layer-backed view, so we do it in `layout()`.
final class BackdropTintView: NSView {
    weak var gradientLayer: CAGradientLayer?

    override func layout() {
        super.layout()
        // Match the sublayer to the view without an implicit resize animation (which would lag the
        // gradient behind a live window resize).
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer?.frame = bounds
        CATransaction.commit()
    }
}
