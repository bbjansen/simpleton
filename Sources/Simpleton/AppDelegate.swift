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
            panelRegistry: panelRegistry,
            onConfigChanged: { [weak self] newConfig in
                self?.config = newConfig
                self?.saveConfig(newConfig)
                self?.updateManager?.setCheckMode(newConfig.general.checkForUpdates)
                self?.applyConfigToAllPanes()  // re-apply appearance (font/cursor/theme) to already-open panes
            },
            onAIConfigChanged: { [weak self] newAIConfig in
                self?.aiConfig = newAIConfig
                self?.aiService?.updateConfig(newAIConfig)
                self?.saveAIConfig(newAIConfig)
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
        // gets in the way of launch/automation, and the restore path isn't end-to-end verified yet.
        // Always start a fresh window. State is still captured below, so restore can be re-enabled
        // by reinstating the shouldRestore check against config.general.restorePreviousSession.
        createNewWindow()

        // Set up session state provider
        sessionManager?.setStateProvider { [weak self] in
            self?.sessionCoordinator.captureSessionState() ?? SessionState()
        }
        sessionManager?.startPeriodicSave()

        // 7. Import wizard check
        showOnboardingIfNeeded()

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
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard config.general.confirmBeforeClosing else { return .terminateNow }

        // Count active SSH sessions across all windows/tabs
        var activeSSHCount = 0
        for wc in windowControllers {
            guard let window = wc.window else { continue }
            let allWindows = window.tabbedWindows ?? [window]
            for w in allWindows {
                guard let tabContainer = w.contentViewController as? TabContainerController else { continue }
                for pane in tabContainer.splitController.panes.values {
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

        // Focus the terminal in the new window
        if let tabContainer = wc.window?.contentViewController as? TabContainerController {
            wc.window?.makeFirstResponder(
                tabContainer.splitController.panes[tabContainer.splitController.focusedPaneID]?.terminalView
            )
        }
    }

    @objc private func windowClosed(_ notification: Notification) {
        guard let wc = notification.object as? WindowController else { return }
        windowControllers.removeAll { $0 === wc }
    }

    /// The active window controller (key window).
    private var activeWindowController: WindowController? {
        windowControllers.first { $0.window?.isKeyWindow == true }
    }

    /// The active split controller, resolved from the key window's content view controller.
    /// This correctly handles native AppKit tabbing where each tab is a separate NSWindow.
    private var activeSplitController: SplitController? {
        guard let window = NSApp.keyWindow,
            let tabContainer = window.contentViewController as? TabContainerController
        else {
            return nil
        }
        return tabContainer.splitController
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
            guard let tabContainer = wc.window?.contentViewController as? TabContainerController else { continue }
            for pane in tabContainer.splitController.panes.values {
                ThemeApplier.apply(theme: theme, config: config, to: pane.terminalView)
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
        for wc in windowControllers {
            wc.updateConfig(config)  // so tabs opened later inherit the current appearance
            let windows = wc.window?.tabGroup?.windows ?? [wc.window].compactMap { $0 }
            for window in windows {
                window.appearance = AppTheme.nsAppearance(
                    for: config.appearance.appearanceMode, isDark: AppTheme.activeTheme.isDark)
                (window.contentViewController as? TabContainerController)?.updateConfig(config)
                window.alphaValue = config.appearance.windowOpacity
            }
        }
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
        guard
            let tabContainer = candidates.compactMap({ $0.contentViewController as? TabContainerController })
                .first
        else { return }
        tabContainer.openSSHConnection(bookmark: bookmark)
    }

    // MARK: - Open Pane (plugin TUI launcher)

    /// Open a shell command (typically a terminal TUI) in a new pane, driven by a plugin's
    /// `open-pane` action. `mode`: "split-right" (default), "split-down", or "tab".
    private func openPaneWithCommand(_ command: String, mode: String) {
        let candidates = [NSApp.keyWindow, activeWindowController?.window].compactMap { $0 }
        guard let window = candidates.first(where: { $0.contentViewController is TabContainerController }),
            let tabContainer = window.contentViewController as? TabContainerController
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

    // MARK: - Updates

    @objc func checkForUpdates() {
        updateManager?.checkForUpdates()
    }

    // MARK: - Workspaces

    @objc func saveWorkspace() {
        sessionCoordinator.saveWorkspace()
    }

    @objc private func openWorkspace(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        sessionCoordinator.openWorkspace(name: name)
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
}
