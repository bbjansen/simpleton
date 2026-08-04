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

    // Auto Layout panel management
    private var contentSplit: NSSplitView?
    private var leftBarHost: NSHostingView<ActivityBarView>?
    private var rightBarHost: NSHostingView<ActivityBarView>?
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
            if isViewLoaded { rebuildActivityBars() }
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
            self?.view.window?.tab.title = title
            self?.view.window?.title = title
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
            aiChatShimObserver, skillPickerShimObserver,
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

        // Central NSSplitView: [leftPanel?] | terminal | [rightPanel?]
        let split = NSSplitView(frame: frame)
        split.isVertical = true
        split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(split)
        contentSplit = split

        // Terminal is always the first arranged subview in contentSplit
        splitController.rootView.frame = frame
        split.addArrangedSubview(splitController.rootView)

        if let registry = panelRegistry {
            mountActivityBars(in: container, registry: registry)
        } else {
            // Fallback: no activity bars — terminal fills the full width
            NSLayoutConstraint.activate([
                split.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                split.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                split.topAnchor.constraint(equalTo: container.topAnchor),
                split.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }

        self.view = container
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        splitController.setFocus(to: splitController.focusedPaneID)
        // Rebind AI Chat panel to this tab's conversation
        panelRegistry?.rebindAIChat(to: tabConversation)
    }

    // MARK: - Activity Bars

    private func mountActivityBars(in container: NSView, registry: PanelRegistry) {
        guard let split = contentSplit else { return }

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
            rightBar.widthAnchor.constraint(equalToConstant: 40),
            // Content split between bars
            split.leadingAnchor.constraint(equalTo: leftBar.trailingAnchor),
            split.trailingAnchor.constraint(equalTo: rightBar.leadingAnchor),
            split.topAnchor.constraint(equalTo: container.topAnchor),
            split.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    private func rebuildActivityBars() {
        guard let registry = panelRegistry else { return }
        let container = view
        leftBarHost?.removeFromSuperview()
        rightBarHost?.removeFromSuperview()
        leftBarHost = nil
        rightBarHost = nil

        // Remove old split-to-container constraints before remounting
        if let split = contentSplit {
            let old = container.constraints.filter {
                ($0.firstItem as? NSView == split || $0.secondItem as? NSView == split)
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
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profile in
                self?.updatePanels(for: profile)
            }
            .store(in: &cancellables)
    }

    // MARK: - Panel Show/Hide

    private func updatePanels(for profile: PanelProfile) {
        guard let split = contentSplit else { return }

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
            self.splitController.setFocus(to: self.splitController.focusedPaneID)
        }
    }

    // MARK: - Context

    /// The container that panel actions should target. Panels are cached and shared across
    /// all tabs by PanelRegistry, so a panel created for the first tab is reused in every
    /// tab. Resolve the ACTIVE tab (the key window's container) at call time so sidebar
    /// actions — opening an SSH host, inserting a command — target the tab the user is on
    /// rather than always the first tab. Falls back to this container.
    private var activePanelContainer: TabContainerController {
        (NSApp.keyWindow?.contentViewController as? TabContainerController) ?? self
    }

    /// Push a fresh app config into this container so cached panels — which read
    /// `appConfig()` lazily — observe changes made in Preferences.
    func updateConfig(_ newConfig: AppConfig) { self.config = newConfig }

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
            self?.view.window?.tab.title = title
            pane.paneLabel = self?.tabConversation?.paneLabels[pane.id] ?? title
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
            self?.view.window?.tab.title = title
            pane.paneLabel = self?.tabConversation?.paneLabels[pane.id] ?? title
        }
        pane.onFocused = { [weak self] focusedPane in
            self?.splitController.setFocus(to: focusedPane.id)
        }
        return pane
    }
}
