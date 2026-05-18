// Sources/Simpleton/AppDelegate.swift
import AppKit
import SwiftUI
import SwiftTerm
import SimpletonCore

class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowControllers: [WindowController] = []
    private var config: AppConfig = AppConfig()
    private var theme: Theme = Theme(name: "default-dark")
    private var sshConfigWatcher: SSHConfigWatcher?
    private var bookmarkStore: BookmarkStore?
    private var quickConnectPanel: QuickConnectPanel?
    private var commandPalettePanel: CommandPalettePanel?
    private var preferencesController: PreferencesWindowController?
    private var sessionManager: SessionManager?
    private var workspaceManager: WorkspaceManager?
    private var workspacesMenu: NSMenu?
    private var isFirstLaunch = false
    private var pluginManager: PluginManager?
    private var aiService: AIService?
    private var aiExplainPanel: AIExplainPanel?
    private var aiConfig: AIConfig = AIConfig()
    private var skillStore: SkillStore?
    private var panelRegistry: PanelRegistry?
    private var terminalActions: TerminalActions!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        // Check App Translocation
        AppTranslocationCheck.checkAndWarn()

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let simpletonDir = appSupport.appendingPathComponent("Simpleton")
        try? FileManager.default.createDirectory(at: simpletonDir, withIntermediateDirectories: true)

        // 1. Load config
        loadConfig()

        // 2. Load bookmarks
        let store = BookmarkStore(directory: simpletonDir)
        Task { try? await store.load() }
        bookmarkStore = store

        // 3. Start SSH config watcher
        sshConfigWatcher = SSHConfigWatcher()
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
                  let pane = sc.panes[sc.focusedPaneID] else { return }
            let bytes = Array(text.utf8)
            pane.terminalView.send(data: bytes[...])
        }
        pluginManager?.commandHandler = { [weak self] commandId in
            self?.pluginManager?.executeCommand(id: commandId)
        }
        pluginManager?.loadAll()

        // Load AI config
        let aiConfigFile = simpletonDir.appendingPathComponent("ai-config.json")
        if FileManager.default.fileExists(atPath: aiConfigFile.path),
           let data = try? Data(contentsOf: aiConfigFile),
           let file = try? JSONDecoder().decode(AIConfigFile.self, from: data) {
            aiConfig = file.config
        }
        aiService = AIService(config: aiConfig)
        // Migrate keychain items from old accessibility level to stop repeated password prompts
        for provider in AIProvider.allCases {
            AIKeychain.migrateAccessibility(for: provider)
        }
        aiExplainPanel = AIExplainPanel()
        let skillStore = SkillStore(appSupportDir: simpletonDir)
        skillStore.load()
        self.skillStore = skillStore

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
        pluginManager?.fireEvent(.onStartup, context: [
            "version": "1.0.0",
            "configDir": simpletonDir.path
        ])

        // 4. Initialize panels
        quickConnectPanel = QuickConnectPanel(bookmarkStore: store, config: config)
        commandPalettePanel = CommandPalettePanel()
        preferencesController = PreferencesWindowController(config: config, pluginManager: pluginManager, aiConfig: aiConfig, skillStore: skillStore, panelRegistry: panelRegistry, onConfigChanged: { [weak self] newConfig in
            self?.config = newConfig
            self?.saveConfig(newConfig)
        }, onAIConfigChanged: { [weak self] newAIConfig in
            self?.aiConfig = newAIConfig
            self?.aiService?.updateConfig(newAIConfig)
            self?.saveAIConfig(newAIConfig)
        })

        // 5. Session restore check
        sessionManager = SessionManager(directory: simpletonDir)
        let shouldRestore = config.general.restorePreviousSession && sessionManager?.didCrashLastSession() ?? false

        // 6. UI launch
        if shouldRestore, let savedState = sessionManager?.loadSavedState(), !savedState.windows.isEmpty {
            showRestorePrompt(state: savedState)
        } else {
            createNewWindow()
        }

        // Set up session state provider
        sessionManager?.setStateProvider { [weak self] in
            self?.captureSessionState() ?? SessionState()
        }
        sessionManager?.startPeriodicSave()

        // 7. Import wizard check
        showOnboardingIfNeeded()

        let menuResult = MenuBarBuilder.build(target: self, workspacesMenuDelegate: self)
        self.workspacesMenu = menuResult.workspacesMenu

        terminalActions = TerminalActions(
            activeSplitController: { [weak self] in self?.activeSplitController },
            activeWindowController: { [weak self] in self?.activeWindowController },
            windowControllers: { [weak self] in self?.windowControllers ?? [] },
            config: { [weak self] in self?.config ?? AppConfig() }
        )

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
        alert.informativeText = "There \(activeSSHCount == 1 ? "is" : "are") \(activeSSHCount) active SSH session\(activeSSHCount == 1 ? "" : "s"). Are you sure you want to quit?"
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
        pluginManager?.fireEvent(.onShutdown, context: ["version": "1.0.0"])
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
              let tabContainer = window.contentViewController as? TabContainerController else {
            return nil
        }
        return tabContainer.splitController
    }

    // MARK: - Config

    private func loadConfig() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let simpletonDir = appSupport.appendingPathComponent("Simpleton")
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
    }

    private func saveConfig(_ config: AppConfig) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let simpletonDir = appSupport.appendingPathComponent("Simpleton")
        try? AtomicFileWriter.writeJSON(ConfigFile(config: config), to: simpletonDir.appendingPathComponent("config.json"))
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
            PaletteAction(title: "Split Right", shortcut: "⌘D", category: "Window") { [weak self] in self?.splitRight() },
            PaletteAction(title: "Split Down", shortcut: "⌘⇧D", category: "Window") { [weak self] in self?.splitDown() },
            PaletteAction(title: "Pick Layout", shortcut: "⌘⇧L", category: "Window") { [weak self] in self?.pickLayout() },
            PaletteAction(title: "Close Pane", shortcut: "⌘W", category: "Window") { [weak self] in self?.closePane() },
            PaletteAction(title: "New Tab", shortcut: "⌘T", category: "Window") { [weak self] in self?.newTab() },
            PaletteAction(title: "New Window", shortcut: "⌘N", category: "Window") { [weak self] in self?.createNewWindow() },
            PaletteAction(title: "Toggle Sidebar", shortcut: "⌘⇧S", category: "View") { [weak self] in self?.toggleSidebar() },
            PaletteAction(title: "Quick Connect", shortcut: "⌘K", category: "SSH") { [weak self] in self?.showQuickConnect() },
            PaletteAction(title: "New Connection", shortcut: nil, category: "SSH") { [weak self] in self?.showNewConnection() },
            PaletteAction(title: "Preferences", shortcut: "⌘,", category: "App") { [weak self] in self?.showPreferences() },
            PaletteAction(title: "Increase Font Size", shortcut: "⌘+", category: "View") { [weak self] in self?.increaseFontSize() },
            PaletteAction(title: "Decrease Font Size", shortcut: "⌘-", category: "View") { [weak self] in self?.decreaseFontSize() },
            PaletteAction(title: "Reset Font Size", shortcut: "⌘0", category: "View") { [weak self] in self?.resetFontSize() },
            PaletteAction(title: "Change Theme", shortcut: nil, category: "App") { [weak self] in self?.showThemePicker() },
            PaletteAction(title: "AI: Chat", shortcut: "\u{2318}\u{21e7}A", category: "AI") { [weak self] in self?.toggleAIChat() },
            PaletteAction(title: "AI: Run Skill", shortcut: "\u{2318}\u{21e7}K", category: "AI") { [weak self] in self?.showSkillPicker() },
            PaletteAction(title: "AI: Explain Selection", shortcut: nil, category: "AI") { [weak self] in self?.explainSelection() },
            PaletteAction(title: "AI: Explain Error", shortcut: nil, category: "AI") { [weak self] in self?.explainLastError() },
        ]

        // Plugin commands
        if let pm = pluginManager {
            for (pluginName, cmd) in pm.pluginCommands {
                actions.append(PaletteAction(
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

    // MARK: - Theme Picker

    @objc private func showThemePicker() {
        guard let window = NSApp.keyWindow,
              let themes = pluginManager?.themeDiscovery.themes else { return }
        let alert = NSAlert()
        alert.messageText = "Choose Theme"
        for theme in themes {
            alert.addButton(withTitle: theme.name)
        }
        alert.addButton(withTitle: "Cancel")

        alert.beginSheetModal(for: window) { [weak self] response in
            let index = Int(response.rawValue) - Int(NSApplication.ModalResponse.alertFirstButtonReturn.rawValue)
            guard let self = self, index >= 0, index < themes.count else { return }
            let selectedTheme = themes[index]
            self.theme = selectedTheme
            self.applyThemeToAllPanes(selectedTheme)
        }
    }

    private func applyThemeToAllPanes(_ theme: Theme) {
        for wc in windowControllers {
            guard let tabContainer = wc.window?.contentViewController as? TabContainerController else { continue }
            for pane in tabContainer.splitController.panes.values {
                ThemeApplier.apply(theme: theme, config: config, to: pane.terminalView)
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
                Task {
                    try? await self?.bookmarkStore?.add(bookmark)
                }
            },
            onCancel: {
                window.endSheet(window.sheets.last ?? window)
            }
        )
        let sheetWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        sheetWindow.contentView = NSHostingView(rootView: formView)
        window.beginSheet(sheetWindow)
    }

    // MARK: - Sidebar

    @objc func toggleSidebar() {
        NotificationCenter.default.post(name: .simpletonToggleSidebar, object: nil)
    }

    // MARK: - AI Actions

    @objc func toggleAIChat() {
        NotificationCenter.default.post(name: .simpletonToggleAIChat, object: aiService)
    }

    @objc func showSkillPicker() {
        guard let ai = aiService, ai.isEnabled else { return }
        NotificationCenter.default.post(name: .simpletonRunSkillPicker, object: ai)
    }

    @objc func explainSelection() {
        guard let ai = aiService, ai.isEnabled,
              let sc = activeSplitController,
              let pane = sc.panes[sc.focusedPaneID] else { return }

        let selected = pane.terminalView.getSelection() ?? ""
        guard !selected.isEmpty else { return }

        aiExplainPanel?.show(
            title: "Explain Selection",
            aiService: ai,
            system: "You are a helpful terminal assistant. Explain the following terminal output or command concisely.",
            user: selected,
            relativeTo: NSApp.keyWindow
        )
    }

    @objc func explainLastError() {
        guard let ai = aiService, ai.isEnabled,
              let sc = activeSplitController,
              let pane = sc.panes[sc.focusedPaneID] else { return }

        let context = AIContextBuilder.build(terminalView: pane.terminalView, recentOutputLines: 50)
        let output = context.recentOutput ?? "(no output captured)"

        aiExplainPanel?.show(
            title: "Explain Error",
            aiService: ai,
            system: "You are a helpful terminal assistant. Explain this error and suggest a fix. Be concise.",
            user: "The command failed. Here is the recent terminal output:\n\n\(output)",
            relativeTo: NSApp.keyWindow
        )
    }

    @objc private func handleExplainError(_ notification: Notification) {
        guard let paneID = notification.object as? PaneID,
              let ai = aiService, ai.isEnabled else { return }

        // Find the pane across all window controllers
        for wc in windowControllers {
            guard let tabContainer = wc.window?.contentViewController as? TabContainerController,
                  let pane = tabContainer.splitController.panes[paneID] else { continue }

            let context = AIContextBuilder.build(terminalView: pane.terminalView, recentOutputLines: 50)
            let output = context.recentOutput ?? "(no output captured)"

            aiExplainPanel?.show(
                title: "Explain Error",
                aiService: ai,
                system: "You are a helpful terminal assistant. Explain this error and suggest a fix. Be concise.",
                user: "The command failed. Here is the recent terminal output:\n\n\(output)",
                relativeTo: pane.terminalView.window
            )
            break
        }
    }

    private func saveAIConfig(_ config: AIConfig) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let simpletonDir = appSupport.appendingPathComponent("Simpleton")
        let aiConfigFile = simpletonDir.appendingPathComponent("ai-config.json")
        if let data = try? JSONEncoder().encode(AIConfigFile(config: config)) {
            try? data.write(to: aiConfigFile)
        }
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

    // MARK: - Connect to Bookmark

    private func connectToBookmark(_ bookmark: Bookmark, in targetWindow: NSWindow? = nil) {
        // Use the provided window, falling back to the key window. Skip windows
        // that aren't terminal windows (e.g. floating panels).
        let candidates = [targetWindow, NSApp.keyWindow].compactMap { $0 }
        guard let window = candidates.first(where: { $0.contentViewController is TabContainerController }),
              let tabContainer = window.contentViewController as? TabContainerController else { return }
        tabContainer.openSSHConnection(bookmark: bookmark)
    }

    // MARK: - Session

    private func captureSessionState() -> SessionState {
        let windowStates = windowControllers.compactMap { wc -> WindowState? in
            guard let window = wc.window else { return nil }
            let frame = WindowFrame(
                x: Double(window.frame.origin.x),
                y: Double(window.frame.origin.y),
                width: Double(window.frame.width),
                height: Double(window.frame.height)
            )
            // Capture tab state from the window's content view controller
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

    private func showRestorePrompt(state: SessionState) {
        let alert = NSAlert()
        alert.messageText = "Restore previous session?"
        alert.informativeText = "Simpleton didn't shut down cleanly. Would you like to restore your previous windows and tabs?"
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Start Fresh")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            restoreSession(state: state)
        } else {
            sessionManager?.clearSavedState()
            createNewWindow()
        }
    }

    private func restoreSession(state: SessionState) {
        for windowState in state.windows {
            let wc = WindowController(config: config, theme: theme)
            wc.bookmarkStore = bookmarkStore
            wc.sshConfigWatcher = sshConfigWatcher
            wc.pluginManager = pluginManager
            windowControllers.append(wc)

            // Apply window frame
            if let window = wc.window {
                let frame = NSRect(
                    x: windowState.frame.x,
                    y: windowState.frame.y,
                    width: windowState.frame.width,
                    height: windowState.frame.height
                )
                window.setFrame(frame, display: true)
            }

            // Restore the first tab's split tree
            if let firstTab = windowState.tabs.first,
               let tabContainer = wc.window?.contentViewController as? TabContainerController {
                restoreSplitTree(firstTab.splitTree, in: tabContainer)
            }

            wc.window?.makeKeyAndOrderFront(nil)
            wc.showWindow(nil)
        }

        if windowControllers.isEmpty {
            createNewWindow()
        }
    }

    private func restoreSplitTree(_ node: SessionSplitNode, in tabContainer: TabContainerController) {
        // For the initial pane (already exists), reconfigure it based on the first pane in the tree
        switch node {
        case .pane(let conn):
            // The initial pane is already running a local shell.
            // If the saved connection was SSH, start SSH instead.
            if case .ssh(let bookmarkId) = conn {
                Task { @MainActor in
                    if let bookmark = await bookmarkStore?.bookmark(for: bookmarkId) {
                        tabContainer.openSSHConnection(bookmark: bookmark)
                    }
                }
            }
            // For local connections, the pane is already running — nothing to do.

        case .split(let direction, let children, _):
            // Apply the layout by splitting the current pane
            // First child reuses the existing pane, subsequent children create new splits
            if children.count >= 2 {
                // Split the current pane for each additional child
                for _ in 1..<children.count {
                    tabContainer.splitController.splitFocusedPane(direction: direction)
                }
                // Now configure each pane based on saved connections
                let paneIDs = tabContainer.splitController.tree.allPaneIDs
                for (index, child) in children.enumerated() {
                    if index < paneIDs.count, case .pane(let conn) = flattenFirstPane(child) {
                        if case .ssh(let bookmarkId) = conn {
                            Task { @MainActor [paneIDs] in
                                if let bookmark = await self.bookmarkStore?.bookmark(for: bookmarkId),
                                   let pane = tabContainer.splitController.panes[paneIDs[index]] {
                                    pane.startSSH(bookmark: bookmark, config: self.config)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Extract the first pane connection from a session split node tree.
    private func flattenFirstPane(_ node: SessionSplitNode) -> SessionSplitNode {
        switch node {
        case .pane: return node
        case .split(_, let children, _):
            return children.first.map { flattenFirstPane($0) } ?? node
        }
    }

    // MARK: - Import Wizard

    private func showOnboardingIfNeeded() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let simpletonDir = appSupport.appendingPathComponent("Simpleton")
        let legacy  = simpletonDir.appendingPathComponent(".wizard-done")
        let current = simpletonDir.appendingPathComponent(".onboarding-done")
        guard !FileManager.default.fileExists(atPath: current.path),
              !FileManager.default.fileExists(atPath: legacy.path) else { return }

        let entries = sshConfigWatcher?.concreteEntries ?? []

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            guard let window = NSApp.keyWindow else { return }

            let panels = self.panelRegistry?.definitions ?? []
            let wizardView = OnboardingWizardView(
                allPanels: panels,
                sshEntries: entries,
                initialAIConfig: self.aiConfig,
                onComplete: { [weak self] profile, newAIConfig, bookmarks, groups in
                    guard let self else { return }
                    window.endSheet(window.sheets.last ?? window)
                    // Save Default profile and activate
                    try? self.panelRegistry?.saveProfile(profile)
                    self.panelRegistry?.activateProfile(profile)
                    // Save AI config if configured
                    if let newAIConfig {
                        self.aiConfig = newAIConfig
                        self.aiService = AIService(config: newAIConfig)
                        self.saveAIConfig(newAIConfig)
                    }
                    // Import bookmarks
                    Task {
                        for bookmark in bookmarks {
                            try? await self.bookmarkStore?.add(bookmark)
                        }
                    }
                    FileManager.default.createFile(atPath: simpletonDir.appendingPathComponent(".onboarding-done").path, contents: nil)
                },
                onSkip: { [weak self] in
                    guard let self else { return }
                    window.endSheet(window.sheets.last ?? window)
                    // Create default profile silently
                    let defaultPanel: [String] = ["connections", "history", "file-browser", "environment", "processes", "ssh-tunnels"]
                    let silentProfile = PanelProfile(
                        id: PanelProfile.defaultProfileID,
                        name: "Default",
                        leftPanelIDs: defaultPanel,
                        rightPanelIDs: ["ai-chat"],
                        leftActivePanelID: "connections",
                        rightActivePanelID: "ai-chat"
                    )
                    try? self.panelRegistry?.saveProfile(silentProfile)
                    self.panelRegistry?.activateProfile(silentProfile)
                    FileManager.default.createFile(atPath: simpletonDir.appendingPathComponent(".onboarding-done").path, contents: nil)
                }
            )

            let sheetWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 550, height: 500),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            sheetWindow.contentView = NSHostingView(rootView: wizardView)
            window.beginSheet(sheetWindow)
        }
    }

    // MARK: - Workspaces

    @objc func saveWorkspace() {
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

            guard let self = self,
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
            try? self.workspaceManager?.save(workspace: workspace)
        }
    }

    @objc private func openWorkspace(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              let workspace = workspaceManager?.load(name: name) else { return }

        // Create a new window and restore the workspace state
        let state = SessionState(windows: [workspace.window])
        restoreSession(state: state)
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
