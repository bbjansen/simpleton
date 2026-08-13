// Sources/Simpleton/AppDelegate.swift
import AppKit
import SimpletonCore
import SwiftTerm
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowControllers: [WindowController] = []
    private var config: AppConfig = AppConfig()

    /// The active terminal palette, derived from the current AppTheme.
    private var theme: Theme {
        Theme(name: AppTheme.activeTheme.name, colors: AppTheme.activeTheme.terminal)
    }
    private var sshConfigWatcher: SSHConfigWatcher?
    private var bookmarkStore: BookmarkStore?
    private var quickConnectPanel: QuickConnectPanel?
    private var commandPalettePanel: CommandPalettePanel?
    private var preferencesController: PreferencesWindowController?
    private var sessionManager: SessionManager?
    private var workspaceManager: WorkspaceManager?
    private var workspacesMenu: NSMenu?
    private var pluginManager: PluginManager?
    private var aiService: AIService?
    private var aiExplainPanel: AIExplainPanel?
    private var aiConfig: AIConfig = AIConfig()
    private var skillStore: SkillStore?
    private var panelRegistry: PanelRegistry?
    private var memoryStore: MemoryStore?
    private var mcpConfigStore: MCPConfigStore?
    private var mcpClients: [MCPClient] = []
    private let workspaceEventBus = WorkspaceEventBus()
    private var terminalActions: TerminalActions!
    private var aiCoordinator: AICoordinator!
    private var onboardingCoordinator: OnboardingCoordinator!
    private var sessionCoordinator: SessionCoordinator!
    private var updateManager: UpdateManager?
    /// Guard against auto-sync feeding back on itself: set while `applyWorkspace` performs its
    /// config/profile/plugin writes, so the change hooks those writes trip don't re-save the workspace.
    private var applyingWorkspace = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Custom in-app tabs replace macOS native window tabbing. Disable automatic tabbing as early
        // as possible so no window ever adopts the system tab bar (which would stack a redundant
        // second bar under the app's custom header). Must run before any NSWindow is created.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        // Check App Translocation
        AppTranslocationCheck.checkAndWarn()

        let simpletonDir = AppPaths.appSupport
        try? FileManager.default.createDirectory(at: simpletonDir, withIntermediateDirectories: true)

        // Write the opt-in shell-integration script (only used when a shell's ZDOTDIR points here).
        let integrationDir = AppPaths.shellIntegrationDir
        try? FileManager.default.createDirectory(at: integrationDir, withIntermediateDirectories: true)
        try? ShellIntegration.zshZshenv.write(
            to: integrationDir.appendingPathComponent(".zshenv"), atomically: true, encoding: .utf8)
        try? ShellIntegration.bashRcfile.write(
            to: integrationDir.appendingPathComponent("bash-rcfile"), atomically: true, encoding: .utf8)

        // 1. Load config
        loadConfig()

        // Follow the system appearance live when in Auto mode: the SwiftUI chrome already adapts via
        // dynamic colors, but the terminal palette must be repainted explicitly.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(systemAppearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil)

        // 2. Load bookmarks
        let store = BookmarkStore(directory: simpletonDir)
        Task {
            do { try await store.load() } catch { print("[Simpleton] Failed to load bookmarks: \(error)") }
        }
        bookmarkStore = store

        // 3. Start SSH config watcher (SIMPLETON_SSH_CONFIG overrides the path for demos/tests)
        let sshConfigPath = ProcessInfo.processInfo.environment["SIMPLETON_SSH_CONFIG"] ?? "~/.ssh/config"
        sshConfigWatcher = SSHConfigWatcher(configPath: sshConfigPath)
        sshConfigWatcher?.onConfigChanged = { _ in }
        sshConfigWatcher?.start()

        // Initialize workspace manager
        let workspacesDir = simpletonDir.appendingPathComponent("workspaces")
        workspaceManager = WorkspaceManager(directory: workspacesDir)
        WorkspaceStore.shared.names = workspaceManager?.listWorkspaces() ?? []

        // Initialize plugin manager
        pluginManager = PluginManager(baseDirectory: simpletonDir)
        pluginManager?.pasteHandler = { [weak self] text in
            // Paste into focused terminal
            guard let sc = self?.activeSplitController,
                let pane = sc.panes[sc.focusedPaneID]
            else { return }
            let bytes = Array(text.utf8)
            pane.terminalView.send(data: bytes[...])
        }
        pluginManager?.commandHandler = { [weak self] commandId in
            self?.pluginManager?.executeCommand(id: commandId)
        }
        pluginManager?.openPaneHandler = { [weak self] command, mode in
            self?.openPaneWithCommand(command, mode: mode)
        }
        pluginManager?.loadAll()

        // Load AI config
        let aiConfigFile = simpletonDir.appendingPathComponent("ai-config.json")
        if FileManager.default.fileExists(atPath: aiConfigFile.path) {
            do {
                let data = try Data(contentsOf: aiConfigFile)
                let file = try JSONDecoder().decode(AIConfigFile.self, from: data)
                aiConfig = file.config
            } catch {
                print("[Simpleton] Failed to load AI config: \(error)")
            }
        }
        aiService = AIService(config: aiConfig)
        // Migrate keychain items off the launch-critical path. retrieveAPIKey can trigger a
        // Keychain access prompt; running it synchronously here would block
        // applicationDidFinishLaunching before any window is shown. SecItem APIs are
        // thread-safe, so migrate on a background queue.
        DispatchQueue.global(qos: .utility).async {
            for provider in AIProvider.allCases {
                AIKeychain.migrateAccessibility(for: provider)
            }
        }
        aiExplainPanel = AIExplainPanel()
        let skillStore = SkillStore(appSupportDir: simpletonDir)
        skillStore.load()
        self.skillStore = skillStore

        // Create memory store
        let memoryDir = simpletonDir.appendingPathComponent("memory")
        self.memoryStore = MemoryStore(storageDir: memoryDir)

        // Load MCP server configs
        let mcpConfigStore = MCPConfigStore(directory: simpletonDir)
        mcpConfigStore.load()
        self.mcpConfigStore = mcpConfigStore

        // Create panel registry and register built-in panels
        let profilesDir = simpletonDir.appendingPathComponent("profiles")
        let panelRegistry = PanelRegistry(profilesDir: profilesDir)
        panelRegistry.loadProfiles()
        panelRegistry.register(.connections)
        panelRegistry.register(.aiChat)
        panelRegistry.register(.skills)
        panelRegistry.register(.notes)
        panelRegistry.register(.snippets)
        panelRegistry.register(.history)
        panelRegistry.register(.environment)
        panelRegistry.register(.fileBrowser)
        panelRegistry.register(.processes)
        panelRegistry.register(.sshTunnels)
        panelRegistry.register(.git)
        panelRegistry.register(.docker)
        panelRegistry.register(.sql)
        // Register JS panels from script plugins
        for plugin in pluginManager?.scriptPlugins ?? [] {
            for panelManifest in plugin.manifest.panels ?? [] {
                let htmlURL = plugin.directory.appendingPathComponent(panelManifest.entrypoint)
                panelRegistry.register(.jsPanel(manifest: panelManifest, htmlURL: htmlURL))
            }
        }
        self.panelRegistry = panelRegistry

        // Fire startup event
        pluginManager?.fireEvent(
            .onStartup,
            context: [
                "version": "0.1.1",
                "configDir": simpletonDir.path,
            ])

        // 4. Initialize panels
        quickConnectPanel = QuickConnectPanel(bookmarkStore: store, config: config)
        commandPalettePanel = CommandPalettePanel()
        preferencesController = PreferencesWindowController(
            config: config, pluginManager: pluginManager, aiConfig: aiConfig, skillStore: skillStore,
            panelRegistry: panelRegistry, workspaceManager: workspaceManager,
            onConfigChanged: { [weak self] newConfig in
                self?.config = newConfig
                self?.saveConfig(newConfig)
                self?.updateManager?.setCheckMode(newConfig.general.checkForUpdates)
                self?.applyConfigToAllPanes()  // re-apply appearance (font/cursor/theme) to already-open panes
                self?.autoSyncActiveWorkspaceIfNeeded()  // keep the active workspace's settings in step
            },
            onAIConfigChanged: { [weak self] newAIConfig in
                self?.aiConfig = newAIConfig
                self?.aiService?.updateConfig(newAIConfig)
                self?.saveAIConfig(newAIConfig)
                self?.autoSyncActiveWorkspaceIfNeeded()
            })

        // Coordinators — constructed before the launch sequence (restore / onboarding) below, which use them.
        terminalActions = TerminalActions(
            activeSplitController: { [weak self] in self?.activeSplitController },
            activeWindowController: { [weak self] in self?.activeWindowController },
            windowControllers: { [weak self] in self?.windowControllers ?? [] },
            config: { [weak self] in self?.config ?? AppConfig() }
        )

        aiCoordinator = AICoordinator(
            aiService: { [weak self] in self?.aiService },
            aiExplainPanel: { [weak self] in self?.aiExplainPanel },
            activeSplitController: { [weak self] in self?.activeSplitController },
            windowControllers: { [weak self] in self?.windowControllers ?? [] }
        )

        onboardingCoordinator = OnboardingCoordinator(
            sshConfigWatcher: { [weak self] in self?.sshConfigWatcher },
            panelRegistry: { [weak self] in self?.panelRegistry },
            aiConfig: { [weak self] in self?.aiConfig ?? AIConfig() },
            bookmarkStore: { [weak self] in self?.bookmarkStore },
            onAIConfigChanged: { [weak self] newAIConfig in
                self?.aiConfig = newAIConfig
                self?.aiService = AIService(config: newAIConfig)
                self?.aiCoordinator.saveAIConfig(newAIConfig)
            }
        )

        sessionCoordinator = SessionCoordinator(
            windowControllers: { [weak self] in self?.windowControllers ?? [] },
            config: { [weak self] in self?.config ?? AppConfig() },
            aiConfig: { [weak self] in self?.aiConfig ?? AIConfig() },
            theme: { [weak self] in self?.theme ?? Theme(name: "default-dark") },
            bookmarkStore: { [weak self] in self?.bookmarkStore },
            sshConfigWatcher: { [weak self] in self?.sshConfigWatcher },
            pluginManager: { [weak self] in self?.pluginManager },
            panelRegistry: { [weak self] in self?.panelRegistry },
            aiService: { [weak self] in self?.aiService },
            skillStore: { [weak self] in self?.skillStore },
            memoryStore: { [weak self] in self?.memoryStore },
            mcpConfigStore: { [weak self] in self?.mcpConfigStore },
            eventBus: { [weak self] in self?.workspaceEventBus },
            workspaceManager: { [weak self] in self?.workspaceManager },
            clearSavedState: { [weak self] in self?.sessionManager?.clearSavedState() },
            createNewWindow: { [weak self] in self?.createNewWindow() },
            addWindowController: { [weak self] wc in self?.windowControllers.append(wc) }
        )

        // 5. Session restore check
        sessionManager = SessionManager(directory: simpletonDir)

        // 6. UI launch
        // Session restore is temporarily disabled: the restore prompt runs a blocking modal that
        // gets in the way of launch/automation. Always start a fresh window. State is still captured
        // below, so restore can be re-enabled by reinstating the shouldRestore check against
        // config.general.restorePreviousSession and calling sessionCoordinator.restoreSession(state:).
        createNewWindow()

        // Default workspace on launch: after the initial window exists, if a default workspace is
        // configured and still exists, apply it. Deferred a tick so the launch window is fully mounted
        // first (the restore path re-parents views into a live window). Skipped under the headless e2e,
        // which drives its own workspace flow.
        if ProcessInfo.processInfo.environment["SIMPLETON_WORKSPACE_E2E"] == nil,
            let defaultWS = config.general.defaultWorkspace,
            workspaceManager?.listWorkspaces().contains(defaultWS) == true
        {
            DispatchQueue.main.async { [weak self] in self?.applyWorkspace(name: defaultWS) }
        }

        // Set up session state provider
        sessionManager?.setStateProvider { [weak self] in
            self?.sessionCoordinator.captureSessionState() ?? SessionState()
        }
        sessionManager?.startPeriodicSave()

        // 7. Import wizard check
        showOnboardingIfNeeded()

        // Headless workspace end-to-end check (set SIMPLETON_WORKSPACE_E2E to run): split the launch
        // window, save it as a workspace, reopen it, and assert the split layout round-tripped — logs
        // "SIMP-WSE2E RESULT PASS/FAIL …" then quits. A no-op unless the env var is set.
        if ProcessInfo.processInfo.environment["SIMPLETON_WORKSPACE_E2E"] != nil {
            runWorkspaceE2E()
        }

        let menuResult = MenuBarBuilder.build(target: self, workspacesMenuDelegate: self)
        self.workspacesMenu = menuResult.workspacesMenu

        updateManager = UpdateManager(checkMode: config.general.checkForUpdates)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowClosed(_:)),
            name: .simpletonWindowClosed,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(splitChanged),
            name: .simpletonSplitChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowNewConnection(_:)),
            name: .simpletonShowNewConnection,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleExplainError(_:)),
            name: .simpletonExplainError,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showPreferences),
            name: .simpletonShowPreferences,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showPreferences),
            name: .openAIPreferences,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenWorkspace(_:)),
            name: .simpletonOpenWorkspace,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSaveWorkspaceRequested),
            name: .simpletonSaveWorkspaceRequested,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWorkspacesChanged),
            name: .simpletonWorkspacesChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWorkspaceSetupChanged),
            name: .simpletonWorkspaceSetupChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUpdateWorkspaceLayout(_:)),
            name: .simpletonUpdateWorkspaceLayout,
            object: nil
        )
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard config.general.confirmBeforeClosing else { return .terminateNow }

        // Count active SSH sessions across all windows/tabs (custom in-app tabs).
        var activeSSHCount = 0
        for wc in windowControllers {
            for tab in wc.tabManager.tabs {
                for pane in tab.container.splitController.panes.values {
                    if case .ssh = pane.connectionType, pane.state == .running {
                        activeSSHCount += 1
                    }
                }
            }
        }

        guard activeSSHCount > 0 else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "Quit Simpleton?"
        alert.informativeText =
            "There \(activeSSHCount == 1 ? "is" : "are") \(activeSSHCount) active SSH session\(activeSSHCount == 1 ? "" : "s"). Are you sure you want to quit?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        return response == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)

        // Disconnect all MCP server processes
        for client in mcpClients {
            client.disconnect()
        }
        mcpClients.removeAll()

        pluginManager?.fireEvent(.onShutdown, context: ["version": "0.1.1"])
        pluginManager?.unloadAll()
        sessionManager?.saveCurrentState()
        sessionManager?.stopAndMarkClean()
    }

    @objc private func splitChanged() {
        sessionManager?.saveCurrentState()
    }

    // MARK: - Window Management

    @objc func createNewWindow() {
        let wc = WindowController(config: config, theme: theme)
        wc.bookmarkStore = bookmarkStore
        wc.sshConfigWatcher = sshConfigWatcher
        wc.pluginManager = pluginManager
        wc.panelRegistry = panelRegistry
        wc.aiService = aiService
        wc.skillStore = skillStore
        wc.memoryStore = memoryStore
        wc.mcpConfigStore = mcpConfigStore
        wc.eventBus = workspaceEventBus
        windowControllers.append(wc)
        wc.window?.center()
        wc.window?.makeKeyAndOrderFront(nil)
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Focus the terminal in the new window's active tab.
        if let tabContainer = wc.tabManager.activeContainer {
            wc.window?.makeFirstResponder(
                tabContainer.splitController.panes[tabContainer.splitController.focusedPaneID]?.terminalView
            )
        }

    }

    @objc private func windowClosed(_ notification: Notification) {
        guard let wc = notification.object as? WindowController else { return }
        windowControllers.removeAll { $0 === wc }
    }

    /// The active window controller (key window). Falls back to the main window (the key window is
    /// often a floating panel — Quick Connect / palette — that owns no WindowController).
    private var activeWindowController: WindowController? {
        windowControllers.first { $0.window?.isKeyWindow == true }
            ?? windowControllers.first { $0.window?.isMainWindow == true }
    }

    /// The active split controller: the active window's active tab's split controller. With custom
    /// in-app tabbing the key window hosts one swappable content view, so resolve through the window
    /// controller's TabManager rather than the window's contentViewController.
    private var activeSplitController: SplitController? {
        activeWindowController?.tabManager.activeContainer?.splitController
    }

    // MARK: - Config

    private func loadConfig() {
        let simpletonDir = AppPaths.appSupport
        let configFile = simpletonDir.appendingPathComponent("config.json")

        if FileManager.default.fileExists(atPath: configFile.path) {
            do {
                let file = try AtomicFileWriter.readJSON(ConfigFile.self, from: configFile)
                self.config = file.config
            } catch {
                self.config = AppConfig()
            }
        } else {
            self.config = AppConfig()
        }
        AppTheme.update(from: config)
    }

    private func saveConfig(_ config: AppConfig) {
        let simpletonDir = AppPaths.appSupport
        do {
            try AtomicFileWriter.writeJSON(
                ConfigFile(config: config), to: simpletonDir.appendingPathComponent("config.json"))
        } catch {
            print("[Simpleton] Failed to save config: \(error)")
        }
    }

    // MARK: - Split Actions

    @objc func splitRight() { terminalActions.splitRight() }
    @objc func splitDown() { terminalActions.splitDown() }
    @objc func closePane() { terminalActions.closePane() }
    @objc func pickLayout() { terminalActions.pickLayout() }
    @objc func togglePaneZoom() { terminalActions.togglePaneZoom() }

    @objc func switchToTabN(_ sender: NSMenuItem) {
        terminalActions.switchToTabN(tag: sender.tag)
    }

    // MARK: - Focus Navigation

    @objc func focusLeft() { terminalActions.focusLeft() }
    @objc func focusRight() { terminalActions.focusRight() }
    @objc func focusUp() { terminalActions.focusUp() }
    @objc func focusDown() { terminalActions.focusDown() }

    // MARK: - Tab Actions

    @objc func newTab() { terminalActions.newTab() }
    @objc func closeTab() { terminalActions.closeTab() }
    @objc func nextTab() { terminalActions.nextTab() }
    @objc func prevTab() { terminalActions.prevTab() }

    // MARK: - Font Actions

    @objc func increaseFontSize() { terminalActions.increaseFontSize() }
    @objc func decreaseFontSize() { terminalActions.decreaseFontSize() }
    @objc func resetFontSize() { terminalActions.resetFontSize() }

    // MARK: - Quick Connect

    @objc func showQuickConnect() {
        guard bookmarkStore != nil else { return }
        if quickConnectPanel?.isVisible == true {
            quickConnectPanel?.dismiss()
            return
        }
        // Capture the terminal window BEFORE showing the panel, because the panel
        // becomes key and NSApp.keyWindow would then point to the panel itself.
        let parentWindow = NSApp.keyWindow
        // Reuse the existing panel instance; do NOT recreate it here.
        quickConnectPanel?.show(relativeTo: parentWindow) { [weak self] bookmark in
            self?.connectToBookmark(bookmark, in: parentWindow)
        }
    }

    // MARK: - Command Palette

    @objc func showCommandPalette() {
        if commandPalettePanel?.isVisible == true {
            commandPalettePanel?.dismiss()
            return
        }
        let actions = buildPaletteActions()
        commandPalettePanel?.show(relativeTo: NSApp.keyWindow, actions: actions)
    }

    private func buildPaletteActions() -> [PaletteAction] {
        var actions = [
            PaletteAction(title: "Split Right", shortcut: "⌘D", category: "Window") { [weak self] in self?.splitRight()
            },
            PaletteAction(title: "Split Down", shortcut: "⌘⇧D", category: "Window") { [weak self] in self?.splitDown()
            },
            PaletteAction(title: "Pick Layout", shortcut: "⌘⇧L", category: "Window") { [weak self] in self?.pickLayout()
            },
            PaletteAction(title: "Close Pane", shortcut: "⌘W", category: "Window") { [weak self] in self?.closePane() },
            PaletteAction(title: "New Tab", shortcut: "⌘T", category: "Window") { [weak self] in self?.newTab() },
            PaletteAction(title: "New Window", shortcut: "⌘N", category: "Window") { [weak self] in
                self?.createNewWindow()
            },
            PaletteAction(title: "Toggle Sidebar", shortcut: "⌘⇧S", category: "View") { [weak self] in
                self?.toggleSidebar()
            },
            PaletteAction(title: "Quick Connect", shortcut: "⌘K", category: "SSH") { [weak self] in
                self?.showQuickConnect()
            },
            PaletteAction(title: "New Connection", shortcut: nil, category: "SSH") { [weak self] in
                self?.showNewConnection()
            },
            PaletteAction(title: "Preferences", shortcut: "⌘,", category: "App") { [weak self] in
                self?.showPreferences()
            },
            PaletteAction(title: "Increase Font Size", shortcut: "⌘+", category: "View") { [weak self] in
                self?.increaseFontSize()
            },
            PaletteAction(title: "Decrease Font Size", shortcut: "⌘-", category: "View") { [weak self] in
                self?.decreaseFontSize()
            },
            PaletteAction(title: "Reset Font Size", shortcut: "⌘0", category: "View") { [weak self] in
                self?.resetFontSize()
            },
            PaletteAction(title: "Appearance Settings", shortcut: nil, category: "App") { [weak self] in
                self?.showPreferences()
            },
            PaletteAction(title: "AI: Chat", shortcut: "\u{2318}\u{21e7}A", category: "AI") { [weak self] in
                self?.toggleAIChat()
            },
            PaletteAction(title: "AI: Run Skill", shortcut: "\u{2318}\u{21e7}K", category: "AI") { [weak self] in
                self?.showSkillPicker()
            },
            PaletteAction(title: "AI: Explain Selection", shortcut: nil, category: "AI") { [weak self] in
                self?.explainSelection()
            },
            PaletteAction(title: "AI: Explain Error", shortcut: nil, category: "AI") { [weak self] in
                self?.explainLastError()
            },
        ]

        // Plugin commands
        if let pm = pluginManager {
            for (pluginName, cmd) in pm.pluginCommands {
                actions.append(
                    PaletteAction(
                        title: cmd.title,
                        shortcut: cmd.shortcut,
                        category: "Plugin: \(pluginName)"
                    ) { [weak self] in
                        self?.pluginManager?.executeCommand(id: cmd.id)
                    })
            }
        }

        return actions
    }

    // MARK: - Preferences

    @objc func showPreferences() {
        preferencesController?.show()
    }

    private func applyThemeToAllPanes(_ theme: Theme) {
        for wc in windowControllers {
            for tab in wc.tabManager.tabs {
                for pane in tab.container.splitController.panes.values {
                    ThemeApplier.apply(theme: theme, config: config, to: pane.terminalView)
                }
            }
        }
    }

    /// Re-apply the current appearance config (font, cursor, theme colors) to every open pane
    /// after the user changes a setting in Preferences — otherwise changes only take effect on
    /// newly-created panes, leaving existing terminals inconsistent until relaunch.
    @objc private func systemAppearanceChanged() {
        // Only Auto follows the system; Dark/Light are pinned. Defer a tick so effectiveAppearance
        // has flipped before we repaint.
        guard config.appearance.appearanceMode.lowercased() == "auto" else { return }
        DispatchQueue.main.async { [weak self] in self?.applyConfigToAllPanes() }
    }

    private func applyConfigToAllPanes() {
        AppTheme.update(from: config)
        applyThemeToAllPanes(theme)
        // Panels are cached globally by PanelRegistry and read their config lazily via the
        // container's `appConfig()` closure. Push the just-stored config into every tab's
        // container so those closures return fresh values after a Preferences change.
        let nsAppearance = AppTheme.nsAppearance(
            for: config.appearance.appearanceMode, isDark: AppTheme.activeTheme.isDark)
        // When the user asks for translucency the window must be non-opaque so the behind-window
        // vibrancy in the chrome can reveal the desktop. The terminal keeps its own opaque background.
        let translucent = config.appearance.chromeTranslucency > 0.001
        let surface = NSColor(hex: AppTheme.activeTheme.chrome.surface)
        for wc in windowControllers {
            wc.updateConfig(config)  // so tabs opened later inherit the current appearance
            // Window-level appearance/opacity/translucency applies once per window.
            if let window = wc.window {
                window.appearance = nsAppearance
                window.alphaValue = config.appearance.windowOpacity
                window.isOpaque = !translucent
                window.backgroundColor = translucent ? .clear : (surface ?? window.backgroundColor)
            }
            // Push fresh config into every tab's container so cached panels re-read it.
            for tab in wc.tabManager.tabs {
                tab.container.updateConfig(config)
            }
        }
        // The Preferences window isn't in windowControllers — retint it (appearance + the dissolved
        // titlebar strip's background) in the same pass so its chrome flips on a live switch too.
        for window in NSApp.windows where window.title == "Preferences" {
            window.appearance = nsAppearance
            window.backgroundColor = surface ?? window.backgroundColor
        }
        // Force every window's chrome to repaint on the NEXT runloop — AFTER SwiftUI has processed
        // the @Published theme change. For a same-appearance switch (e.g. Nord→Dracula) the body
        // re-eval is async; a synchronous repaint here composites the PRE-update body, leaving the
        // fresh render deferred on any non-key window until it next became key (the "panels don't
        // change until I click them" bug). Data: forceAppearanceRepaint fired before SidebarView.body.
        DispatchQueue.main.async { [weak self] in self?.repaintChromeOnAllWindows() }
    }

    private func repaintChromeOnAllWindows() {
        // One window per WindowController now (custom in-app tabs). Poking the window's content view
        // tree repaints the header, tab strip, and the active tab's chrome. Inactive tab containers
        // are detached from the view hierarchy and re-render when next swapped in.
        for wc in windowControllers {
            if let window = wc.window { forceAppearanceRepaint(window) }
        }
        for window in NSApp.windows where window.title == "Preferences" {
            forceAppearanceRepaint(window)
        }
    }

    /// Force an immediate, synchronized repaint of a window's chrome after a theme/appearance change.
    /// Setting `window.appearance` alone leaves a non-key window's `effectiveAppearance` — and thus its
    /// NSHostingView `colorScheme` environment and NSVisualEffectView materials — stale until the window
    /// next becomes key. That is the "panels stay dark until I click the window" symptom. Poking
    /// layout/display down the whole view tree, then `displayIfNeeded()`, flushes the pending SwiftUI
    /// re-render and recomposites the vibrancy immediately. Ref: WWDC 2018 "Advanced Dark Mode" (218)
    /// + Apple DTS forums thread 104515.
    private func forceAppearanceRepaint(_ window: NSWindow) {
        guard let content = window.contentView else { return }
        func poke(_ view: NSView) {
            view.needsLayout = true
            view.needsDisplay = true
            for sub in view.subviews { poke(sub) }
        }
        poke(content)
        window.displayIfNeeded()
    }

    // MARK: - New Connection

    @objc func showNewConnection() {
        showNewConnectionSheet(on: NSApp.keyWindow)
    }

    @objc private func handleShowNewConnection(_ notification: Notification) {
        // The notification may carry the originating window as its object
        let window = (notification.object as? NSWindow) ?? NSApp.keyWindow
        showNewConnectionSheet(on: window)
    }

    private func showNewConnectionSheet(on window: NSWindow?) {
        guard let window = window else { return }
        let newBookmark = Bookmark(name: "", host: "")
        let formView = ConnectionFormView(
            bookmark: newBookmark,
            isNew: true,
            onSave: { [weak self] bookmark in
                window.endSheet(window.sheets.last ?? window)
                guard let store = self?.bookmarkStore else { return }
                Task {
                    try? await store.add(bookmark)
                }
            },
            onCancel: {
                window.endSheet(window.sheets.last ?? window)
            }
        )
        let sheetWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600), styleMask: [.titled], backing: .buffered,
            defer: false)
        sheetWindow.contentView = NSHostingView(rootView: formView)
        window.beginSheet(sheetWindow)
    }

    // MARK: - Sidebar

    @objc func toggleSidebar() {
        NotificationCenter.default.post(name: .simpletonToggleSidebar, object: nil)
    }

    // MARK: - AI Actions

    @objc func toggleAIChat() { aiCoordinator.toggleAIChat() }
    @objc func showSkillPicker() { aiCoordinator.showSkillPicker() }
    @objc func explainSelection() { aiCoordinator.explainSelection() }
    @objc func explainLastError() { aiCoordinator.explainLastError() }

    @objc private func handleExplainError(_ notification: Notification) {
        guard let paneID = notification.object as? PaneID else { return }
        aiCoordinator.handleExplainError(paneID: paneID)
    }

    private func saveAIConfig(_ config: AIConfig) {
        aiCoordinator.saveAIConfig(config)
    }

    // MARK: - Scrollback Search

    @objc func showScrollbackSearch() {
        NotificationCenter.default.post(name: .simpletonShowSearch, object: nil)
    }

    @objc func clearTerminal() {
        guard let pane = activeSplitController?.panes[activeSplitController?.focusedPaneID ?? UUID()] else { return }
        // Send Ctrl+L (form feed) to clear the terminal, then "clear" command for a full reset
        pane.terminalView.send(data: Array("\u{0C}".utf8)[...])
    }

    // MARK: - Prompt Navigation

    @objc func previousPrompt() {
        guard let sc = activeSplitController,
            let pane = sc.panes[sc.focusedPaneID]
        else { return }
        pane.navigateToPreviousPrompt()
    }

    @objc func nextPrompt() {
        guard let sc = activeSplitController,
            let pane = sc.panes[sc.focusedPaneID]
        else { return }
        pane.navigateToNextPrompt()
    }

    @objc func selectCommandOutput() {
        guard let sc = activeSplitController,
            let pane = sc.panes[sc.focusedPaneID]
        else { return }
        pane.selectCommandOutput()
    }

    // MARK: - Connect to Bookmark

    private func connectToBookmark(_ bookmark: Bookmark, in targetWindow: NSWindow? = nil) {
        // Use the provided window, falling back to the key window. Skip windows
        // that aren't terminal windows (e.g. floating panels).
        // The key window is often a floating panel (Quick Connect / palette) with no
        // contentViewController, so prefer mainWindow (stays the terminal under a panel), then the
        // captured target, then any terminal front-to-back.
        let candidates =
            [NSApp.mainWindow, targetWindow, NSApp.keyWindow].compactMap { $0 }
            + NSApp.orderedWindows
        guard let tabContainer = candidates.compactMap({ $0.activeTabContainer }).first
        else { return }
        tabContainer.openSSHConnection(bookmark: bookmark)
    }

    // MARK: - Open Pane (plugin TUI launcher)

    /// Open a shell command (typically a terminal TUI) in a new pane, driven by a plugin's
    /// `open-pane` action. `mode`: "split-right" (default), "split-down", or "tab".
    private func openPaneWithCommand(_ command: String, mode: String) {
        let candidates = [NSApp.keyWindow, activeWindowController?.window].compactMap { $0 }
        guard let tabContainer = candidates.compactMap({ $0.activeTabContainer }).first
        else { return }

        switch mode.lowercased() {
        case "tab":
            activeWindowController?.newTab().runCommandInFocusedPane(command)
        case "split-down", "down":
            tabContainer.openCommandPane(command: command, direction: .horizontal)
        default:
            tabContainer.openCommandPane(command: command, direction: .vertical)
        }
    }

    // MARK: - Onboarding

    private func showOnboardingIfNeeded() {
        onboardingCoordinator.showOnboardingIfNeeded()
    }

    // MARK: - Workspace end-to-end check

    /// Headless e2e for Workspaces: split the launch window into two panes, capture+save it as a
    /// workspace, reopen it (real WorkspaceManager load + SessionCoordinator restore), and assert a
    /// fresh window came back with the two-pane split at the saved size. Timing-based (the split +
    /// restore rebuild views), so it uses generous delays. Logs one `SIMP-WSE2E RESULT …` line, cleans
    /// up the temp workspace, and quits. Gated behind SIMPLETON_WORKSPACE_E2E.
    private func runWorkspaceE2E() {
        NSLog("SIMP-WSE2E starting")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self = self, let originalWC = self.windowControllers.first,
                let win = originalWC.window
            else {
                NSLog("SIMP-WSE2E RESULT FAIL: no launch window")
                NSApp.terminate(nil)
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            // Use a realistic frame (headless launch lands at the 400px minimum, where a 2-pane split
            // clamps the restore to the content minimum and the frame can't round-trip exactly).
            win.setFrame(NSRect(x: 120, y: 120, width: 1000, height: 700), display: true)
            win.makeKeyAndOrderFront(nil)
            // Put the app on a distinctive theme AND font so the workspace captures the whole setup and
            // we can verify deeper prefs (not just the layout/theme) re-apply on open.
            self.config.appearance.appearanceMode = "nebula"
            self.config.appearance.fontFamily = "Courier New"
            let initialPanes = originalWC.activeSplitController.panes.count
            // Split directly on the window's split controller (not the keyWindow-based splitRight(),
            // which doesn't resolve for a headlessly-launched app).
            originalWC.activeSplitController.splitFocusedPane(direction: .vertical)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let splitPanes = originalWC.activeSplitController.panes.count
                let saved = self.sessionCoordinator.saveWorkspaceState(name: "__e2e__", from: win)
                let savedSize = win.frame.size
                // Move off the workspace's theme AND font so applying it has an observable effect.
                self.config.appearance.appearanceMode = "dark"
                self.config.appearance.fontFamily = "SF Mono"
                let wcCountBefore = self.windowControllers.count
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    // Apply the full workspace (settings + layout), not just the layout.
                    self.applyWorkspace(name: "__e2e__")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        let restoredWC = self.windowControllers.last
                        let restoredPanes = restoredWC?.activeSplitController.panes.count ?? 0
                        let restoredSize = restoredWC?.window?.frame.size ?? .zero
                        let newWindow = self.windowControllers.count == wcCountBefore + 1
                        let themeApplied = self.config.appearance.appearanceMode == "nebula"
                        // Deeper-prefs round-trip: the captured font came back via ws.preferences.
                        let fontApplied = self.config.appearance.fontFamily == "Courier New"
                        let frameOK =
                            abs(restoredSize.width - savedSize.width) < 3
                            && abs(restoredSize.height - savedSize.height) < 3
                        // Phase 2 (replace-window): with the replace option on, re-applying the
                        // workspace REPLACES all existing windows — it opens one new window and closes
                        // every prior one, so exactly one window must remain (regardless of how many
                        // there were). Count settled windows after the close animation.
                        let beforeReplace = self.windowControllers.count
                        self.config.general.workspaceOpenReplacesWindow = true
                        self.applyWorkspace(name: "__e2e__")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            let afterReplace = self.windowControllers.count
                            // Replace collapses to a single (the freshly restored) window.
                            let replaceOK = beforeReplace >= 1 && afterReplace == 1
                            self.config.general.workspaceOpenReplacesWindow = false
                            let pass =
                                saved && initialPanes == 1 && splitPanes == 2 && newWindow
                                && restoredPanes == 2 && frameOK && themeApplied && fontApplied
                                && replaceOK
                            NSLog(
                                "SIMP-WSE2E RESULT \(pass ? "PASS" : "FAIL"): saved=\(saved) "
                                    + "initialPanes=\(initialPanes) splitPanes=\(splitPanes) "
                                    + "newWindow=\(newWindow) restoredPanes=\(restoredPanes) "
                                    + "frameOK=\(frameOK) themeApplied=\(themeApplied)(\(self.config.appearance.appearanceMode)) "
                                    + "fontApplied=\(fontApplied)(\(self.config.appearance.fontFamily)) "
                                    + "replaceOK=\(replaceOK)(before=\(beforeReplace) after=\(afterReplace)) "
                                    + "savedSize=\(savedSize) restoredSize=\(restoredSize)")
                            self.workspaceManager?.delete(name: "__e2e__")
                            NSApp.terminate(nil)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Updates

    @objc func checkForUpdates() {
        updateManager?.checkForUpdates()
    }

    // MARK: - Workspaces

    @objc func saveWorkspace() {
        sessionCoordinator.saveWorkspace()
    }

    /// Re-read the saved-workspace list into the observable store (drives the header dropdown and the
    /// Settings tab). Call after any save/delete.
    private func refreshWorkspaceStore() {
        WorkspaceStore.shared.names = workspaceManager?.listWorkspaces() ?? []
    }

    /// `.simpletonOpenWorkspace` (object = the workspace name) — apply that workspace's whole setup.
    @objc private func handleOpenWorkspace(_ note: Notification) {
        guard let name = note.object as? String else { return }
        applyWorkspace(name: name)
    }

    /// Re-capture the active terminal window's layout into an existing workspace, keeping all of its
    /// saved settings (preferences/AI/profile/plugins/theme). Targets the key terminal window, falling
    /// back to the first tracked terminal (from Settings the key window is the Preferences sheet).
    /// Broadcasts `.simpletonWorkspacesChanged` so observers refresh.
    func updateWorkspaceLayout(name: String) {
        let target =
            NSApp.keyWindow?.activeTabContainer != nil ? NSApp.keyWindow : windowControllers.first?.window
        guard let window = target,
            let windowState = sessionCoordinator.captureWindowState(from: window),
            var ws = workspaceManager?.load(name: name)
        else { return }
        ws.window = windowState
        ws.savedAt = Date()
        try? workspaceManager?.save(workspace: ws)
        NotificationCenter.default.post(name: .simpletonWorkspacesChanged, object: nil)
    }

    /// `.simpletonSaveWorkspaceRequested` — prompt for a name and save the current window. The save
    /// runs as an async naming sheet, so refresh shortly after here as a fallback; the definitive
    /// refresh is `.simpletonWorkspacesChanged`, which the save path can post once it lands.
    @objc private func handleSaveWorkspaceRequested() {
        saveWorkspace()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshWorkspaceStore()
        }
    }

    /// `.simpletonWorkspacesChanged` — the saved set changed (Settings edit/delete, or a completed
    /// save) — re-read the list.
    @objc private func handleWorkspacesChanged() {
        refreshWorkspaceStore()
    }

    /// `.simpletonWorkspaceSetupChanged` — a setup facet (profile / plugins) changed. Re-sync the
    /// active workspace if auto-sync is on.
    @objc private func handleWorkspaceSetupChanged() {
        autoSyncActiveWorkspaceIfNeeded()
    }

    /// `.simpletonUpdateWorkspaceLayout` (object = the workspace name) — re-capture the current
    /// window's layout into that workspace.
    @objc private func handleUpdateWorkspaceLayout(_ note: Notification) {
        guard let name = note.object as? String else { return }
        updateWorkspaceLayout(name: name)
    }

    /// If auto-sync is enabled and a workspace is active, re-save that workspace's SETTINGS —
    /// preferences (theme/font/cursor/SSH/…), AI config, active panel profile, enabled plugins — while
    /// KEEPING its saved layout (`window`) untouched (syncing the layout on every tweak would be too
    /// churny). Skipped while `applyWorkspace` is running so applying a workspace never re-saves it.
    private func autoSyncActiveWorkspaceIfNeeded() {
        guard config.general.autoSyncActiveWorkspace, !applyingWorkspace,
            let name = WorkspaceStore.shared.activeName,
            let manager = workspaceManager,
            var ws = manager.load(name: name)
        else { return }

        ws.preferences = SessionCoordinator.capturablePreferences(from: config)
        ws.aiConfig = aiConfig
        ws.appearanceMode = config.appearance.appearanceMode
        ws.accentColor = config.appearance.accentColor
        MainActor.assumeIsolated {
            ws.panelProfileID = self.panelRegistry?.activeProfile.id.uuidString
            ws.enabledPlugins = self.pluginManager?.scriptPlugins.filter(\.isEnabled).map(\.name)
        }
        try? manager.save(workspace: ws)
    }

    @objc private func openWorkspace(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        applyWorkspace(name: name)
    }

    /// Open a workspace: apply its whole setup — full preferences (theme, font, cursor, SSH, general),
    /// AI config, panel profile, enabled plugins — then restore its saved layout in a window. Nil setup
    /// fields are left unchanged, so a layout-only workspace (saved before this feature) still just
    /// restores its panes. When `general.workspaceOpenReplacesWindow` is set, the restored layout
    /// replaces the current windows instead of adding one.
    func applyWorkspace(name: String) {
        guard let ws = workspaceManager?.load(name: name) else { return }
        // Applying a workspace must not trigger auto-sync of itself: suppress the sync hook for the
        // duration of the config/profile/plugin writes this method performs.
        applyingWorkspace = true
        defer { applyingWorkspace = false }
        WorkspaceStore.shared.activeName = name

        // 1. Preferences. Prefer the full captured AppConfig (font/cursor/SSH/terminal + theme); fall
        //    back to the legacy appearanceMode/accent fields for pre-feature workspace files.
        if var prefs = ws.preferences {
            // CRITICAL: preserve the GLOBAL workspace-management fields across the swap. They are
            // app-wide (default-on-launch, replace-window, auto-sync) and must survive opening any
            // workspace — otherwise this write would clobber them (and could cause a default-open loop).
            prefs.general.defaultWorkspace = config.general.defaultWorkspace
            prefs.general.workspaceOpenReplacesWindow = config.general.workspaceOpenReplacesWindow
            prefs.general.autoSyncActiveWorkspace = config.general.autoSyncActiveWorkspace
            config = prefs
            saveConfig(config)
            applyConfigToAllPanes()
        } else {
            var appearanceChanged = false
            if let mode = ws.appearanceMode {
                config.appearance.appearanceMode = mode
                appearanceChanged = true
            }
            if let accent = ws.accentColor {
                config.appearance.accentColor = accent
                appearanceChanged = true
            }
            if appearanceChanged {
                saveConfig(config)
                applyConfigToAllPanes()
            }
        }

        // 1b. AI config — swap the provider/model, push it into the live service, and persist.
        if let ai = ws.aiConfig {
            aiConfig = ai
            aiService?.updateConfig(ai)
            saveAIConfig(ai)
        }

        // 1c. Keep the Preferences window's cached config/AI in step with this out-of-band change, so
        //     the next Settings open (or the currently-open one) shows the applied workspace's values
        //     instead of a stale snapshot that a later edit would persist back over the workspace.
        preferencesController?.externalConfigDidChange(config: config, aiConfig: aiConfig)

        // 2 + 3. Panel profile + enabled plugins. PanelRegistry/PluginManager are @MainActor; this
        // runs on the main thread (menu action / e2e), so touch them under assumeIsolated.
        MainActor.assumeIsolated {
            if let profileID = ws.panelProfileID,
                let profile = self.panelRegistry?.profiles.first(where: { $0.id.uuidString == profileID })
            {
                self.panelRegistry?.activateProfile(profile)
            }
            if let enabled = ws.enabledPlugins, let pm = self.pluginManager {
                for plugin in pm.scriptPlugins {
                    pm.setEnabled(enabled.contains(plugin.name), for: plugin)
                }
            }
        }

        // 4. Restore the saved layout. Capture the pre-restore windows first: openWorkspace appends a
        //    new WindowController, so if "replace" is on we close the *old* ones AFTER the new window
        //    exists — a window is always present, so the app never quits mid-restore.
        let previousControllers = windowControllers
        sessionCoordinator.openWorkspace(name: name)
        if config.general.workspaceOpenReplacesWindow {
            for wc in previousControllers { wc.window?.close() }
        }
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === workspacesMenu else { return }
        menu.removeAllItems()
        let names = workspaceManager?.listWorkspaces() ?? []
        if names.isEmpty {
            let emptyItem = NSMenuItem(title: "No saved workspaces", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for name in names {
                let item = NSMenuItem(title: name, action: #selector(openWorkspace(_:)), keyEquivalent: "")
                item.representedObject = name
                menu.addItem(item)
            }
        }
    }
}

extension Notification.Name {
    static let simpletonToggleSidebar = Notification.Name("simpletonToggleSidebar")
    static let simpletonShowSearch = Notification.Name("simpletonShowSearch")
    static let simpletonSplitChanged = Notification.Name("simpletonSplitChanged")
    static let simpletonShowNewConnection = Notification.Name("simpletonShowNewConnection")
    static let openAIPreferences = Notification.Name("simpletonOpenAIPreferences")
    /// Open a workspace by name (object = the workspace name String).
    static let simpletonOpenWorkspace = Notification.Name("simpletonOpenWorkspace")
    /// Prompt to save the current window as a workspace.
    static let simpletonSaveWorkspaceRequested = Notification.Name("simpletonSaveWorkspaceRequested")
    /// The saved-workspaces set changed (created / renamed / deleted) — re-read the list.
    static let simpletonWorkspacesChanged = Notification.Name("simpletonWorkspacesChanged")
    /// A facet of the active setup changed (panel profile activated, plugin enablement toggled) —
    /// AppDelegate re-saves the active workspace's settings if auto-sync is enabled.
    static let simpletonWorkspaceSetupChanged = Notification.Name("simpletonWorkspaceSetupChanged")
    /// Re-capture the active window's layout into a workspace by name (object = the workspace name).
    static let simpletonUpdateWorkspaceLayout = Notification.Name("simpletonUpdateWorkspaceLayout")
}
