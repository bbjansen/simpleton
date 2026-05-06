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
    private var isFirstLaunch = false

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

        // 4. Initialize panels
        quickConnectPanel = QuickConnectPanel(bookmarkStore: store, config: config)
        commandPalettePanel = CommandPalettePanel()
        preferencesController = PreferencesWindowController(config: config) { [weak self] newConfig in
            self?.config = newConfig
            self?.saveConfig(newConfig)
        }

        // Initialize workspace manager
        let workspacesDir = simpletonDir.appendingPathComponent("workspaces")
        workspaceManager = WorkspaceManager(directory: workspacesDir)

        // 5. Session restore check
        sessionManager = SessionManager(directory: simpletonDir)
        let shouldRestore = config.general.restorePreviousSession && sessionManager!.didCrashLastSession()

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
        checkFirstLaunchWizard()

        buildMenuBar()

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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessionManager?.saveCurrentState()
        sessionManager?.stopAndMarkClean()
    }

    @objc private func splitChanged() {
        sessionManager?.saveCurrentState()
    }

    // MARK: - Window Management

    @objc func createNewWindow() {
        let wc = WindowController(config: config, theme: theme)
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

    // MARK: - Menu Bar

    private func buildMenuBar() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Simpleton", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Preferences...", action: #selector(showPreferences), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Simpleton", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Window", action: #selector(createNewWindow), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "New Tab", action: #selector(newTab), keyEquivalent: "t")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "New Connection...", action: #selector(showNewConnection), keyEquivalent: "")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Pane", action: #selector(closePane), keyEquivalent: "w")

        let closeTabItem = NSMenuItem(title: "Close Tab", action: #selector(closeTab), keyEquivalent: "W")
        closeTabItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(closeTabItem)

        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Find...", action: #selector(showScrollbackSearch), keyEquivalent: "f")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Increase Font Size", action: #selector(increaseFontSize), keyEquivalent: "=")
        viewMenu.addItem(withTitle: "Decrease Font Size", action: #selector(decreaseFontSize), keyEquivalent: "-")
        viewMenu.addItem(withTitle: "Reset Font Size", action: #selector(resetFontSize), keyEquivalent: "0")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Split menu
        let splitMenuItem = NSMenuItem()
        let splitMenu = NSMenu(title: "Split")
        splitMenu.addItem(withTitle: "Split Right", action: #selector(splitRight), keyEquivalent: "d")

        let splitDownItem = NSMenuItem(title: "Split Down", action: #selector(splitDown), keyEquivalent: "D")
        splitDownItem.keyEquivalentModifierMask = [.command, .shift]
        splitMenu.addItem(splitDownItem)

        splitMenu.addItem(.separator())

        let layoutItem = NSMenuItem(title: "Pick Layout…", action: #selector(pickLayout), keyEquivalent: "L")
        layoutItem.keyEquivalentModifierMask = [.command, .shift]
        splitMenu.addItem(layoutItem)

        splitMenu.addItem(.separator())

        // Focus navigation
        let focusLeftItem = NSMenuItem(title: "Focus Left", action: #selector(focusLeft), keyEquivalent: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)))
        focusLeftItem.keyEquivalentModifierMask = [.command, .option]
        splitMenu.addItem(focusLeftItem)

        let focusRightItem = NSMenuItem(title: "Focus Right", action: #selector(focusRight), keyEquivalent: String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)))
        focusRightItem.keyEquivalentModifierMask = [.command, .option]
        splitMenu.addItem(focusRightItem)

        let focusUpItem = NSMenuItem(title: "Focus Up", action: #selector(focusUp), keyEquivalent: String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)))
        focusUpItem.keyEquivalentModifierMask = [.command, .option]
        splitMenu.addItem(focusUpItem)

        let focusDownItem = NSMenuItem(title: "Focus Down", action: #selector(focusDown), keyEquivalent: String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)))
        focusDownItem.keyEquivalentModifierMask = [.command, .option]
        splitMenu.addItem(focusDownItem)

        splitMenuItem.submenu = splitMenu
        mainMenu.addItem(splitMenuItem)

        // SSH menu
        let sshMenuItem = NSMenuItem()
        let sshMenu = NSMenu(title: "SSH")

        let quickConnectItem = NSMenuItem(title: "Quick Connect...", action: #selector(showQuickConnect), keyEquivalent: "k")
        sshMenu.addItem(quickConnectItem)

        sshMenu.addItem(withTitle: "New Connection...", action: #selector(showNewConnection), keyEquivalent: "")

        let toggleSidebarItem = NSMenuItem(title: "Toggle Sidebar", action: #selector(toggleSidebar), keyEquivalent: "S")
        toggleSidebarItem.keyEquivalentModifierMask = [.command, .shift]
        sshMenu.addItem(toggleSidebarItem)

        sshMenuItem.submenu = sshMenu
        mainMenu.addItem(sshMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")

        let nextTabItem = NSMenuItem(title: "Next Tab", action: #selector(nextTab), keyEquivalent: "}")
        nextTabItem.keyEquivalentModifierMask = [.command, .shift]
        windowMenu.addItem(nextTabItem)

        let prevTabItem = NSMenuItem(title: "Previous Tab", action: #selector(prevTab), keyEquivalent: "{")
        prevTabItem.keyEquivalentModifierMask = [.command, .shift]
        windowMenu.addItem(prevTabItem)

        windowMenu.addItem(.separator())
        let saveWorkspaceItem = NSMenuItem(title: "Save Workspace...", action: #selector(saveWorkspace), keyEquivalent: "S")
        saveWorkspaceItem.keyEquivalentModifierMask = [.command, .option]
        windowMenu.addItem(saveWorkspaceItem)

        // Workspace submenu
        let workspacesItem = NSMenuItem(title: "Workspaces", action: nil, keyEquivalent: "")
        let workspacesMenu = NSMenu(title: "Workspaces")
        let workspaceNames = workspaceManager?.listWorkspaces() ?? []
        if workspaceNames.isEmpty {
            let emptyItem = NSMenuItem(title: "No saved workspaces", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            workspacesMenu.addItem(emptyItem)
        } else {
            for name in workspaceNames {
                let item = NSMenuItem(title: name, action: #selector(openWorkspace(_:)), keyEquivalent: "")
                item.representedObject = name
                workspacesMenu.addItem(item)
            }
        }
        workspacesItem.submenu = workspacesMenu
        windowMenu.addItem(workspacesItem)

        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        // Help menu
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        let paletteItem = NSMenuItem(title: "Command Palette...", action: #selector(showCommandPalette), keyEquivalent: "P")
        paletteItem.keyEquivalentModifierMask = [.command, .shift]
        helpMenu.addItem(paletteItem)
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    // MARK: - Split Actions

    @objc private func splitRight() {
        activeSplitController?.splitFocusedPane(direction: .vertical)
    }

    @objc private func splitDown() {
        activeSplitController?.splitFocusedPane(direction: .horizontal)
    }

    @objc private func closePane() {
        guard let sc = activeSplitController else { return }
        sc.closePane(sc.focusedPaneID)
    }

    @objc private func pickLayout() {
        guard let window = NSApp.keyWindow,
              let sc = activeSplitController else { return }

        let alert = NSAlert()
        alert.messageText = "Pick Layout"
        alert.informativeText = "Choose a layout for this tab."
        for layout in PredefinedLayouts.all {
            alert.addButton(withTitle: layout.name)
        }
        alert.addButton(withTitle: "Cancel")

        alert.beginSheetModal(for: window) { response in
            let index = Int(response.rawValue) - Int(NSApplication.ModalResponse.alertFirstButtonReturn.rawValue)
            guard index >= 0, index < PredefinedLayouts.all.count else { return }
            let layout = PredefinedLayouts.all[index]
            sc.applyLayout(layout)
        }
    }

    // MARK: - Focus Navigation

    @objc private func focusLeft() {
        activeSplitController?.moveFocus(.left)
    }
    @objc private func focusRight() {
        activeSplitController?.moveFocus(.right)
    }
    @objc private func focusUp() {
        activeSplitController?.moveFocus(.up)
    }
    @objc private func focusDown() {
        activeSplitController?.moveFocus(.down)
    }

    // MARK: - Tab Actions

    @objc private func newTab() {
        // Find the WindowController that owns the key window (or its tab group)
        guard let keyWindow = NSApp.keyWindow else { return }
        if let wc = windowControllers.first(where: { $0.window === keyWindow || $0.window?.tabbedWindows?.contains(keyWindow) == true }) {
            wc.newTab()
        } else {
            activeWindowController?.newTab()
        }
    }

    @objc private func closeTab() {
        NSApp.keyWindow?.close()
    }

    @objc private func nextTab() {
        NSApp.keyWindow?.selectNextTab(nil)
    }

    @objc private func prevTab() {
        NSApp.keyWindow?.selectPreviousTab(nil)
    }

    // MARK: - Font Actions

    @objc private func increaseFontSize() {
        guard let sc = activeSplitController else { return }
        for pane in sc.panes.values {
            let size = pane.terminalView.font.pointSize
            pane.terminalView.font = pane.terminalView.font.withSize(size + 1)
        }
    }

    @objc private func decreaseFontSize() {
        guard let sc = activeSplitController else { return }
        for pane in sc.panes.values {
            let size = pane.terminalView.font.pointSize
            if size > 8 {
                pane.terminalView.font = pane.terminalView.font.withSize(size - 1)
            }
        }
    }

    @objc private func resetFontSize() {
        guard let sc = activeSplitController else { return }
        let defaultSize = CGFloat(config.appearance.fontSize)
        for pane in sc.panes.values {
            pane.terminalView.font = pane.terminalView.font.withSize(defaultSize)
        }
    }

    // MARK: - Quick Connect

    @objc private func showQuickConnect() {
        guard let store = bookmarkStore else { return }
        if quickConnectPanel?.isVisible == true {
            quickConnectPanel?.dismiss()
            return
        }
        quickConnectPanel = QuickConnectPanel(bookmarkStore: store, config: config)
        quickConnectPanel?.show(relativeTo: NSApp.keyWindow) { [weak self] bookmark in
            self?.connectToBookmark(bookmark)
        }
    }

    // MARK: - Command Palette

    @objc private func showCommandPalette() {
        if commandPalettePanel?.isVisible == true {
            commandPalettePanel?.dismiss()
            return
        }
        let actions = buildPaletteActions()
        commandPalettePanel?.show(relativeTo: NSApp.keyWindow, actions: actions)
    }

    private func buildPaletteActions() -> [PaletteAction] {
        [
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
        ]
    }

    // MARK: - Preferences

    @objc private func showPreferences() {
        preferencesController?.show()
    }

    // MARK: - New Connection

    @objc private func showNewConnection() {
        guard let window = NSApp.keyWindow else { return }
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

    @objc private func toggleSidebar() {
        NotificationCenter.default.post(name: .simpletonToggleSidebar, object: nil)
    }

    // MARK: - Scrollback Search

    @objc private func showScrollbackSearch() {
        NotificationCenter.default.post(name: .simpletonShowSearch, object: nil)
    }

    // MARK: - Connect to Bookmark

    private func connectToBookmark(_ bookmark: Bookmark) {
        guard let window = NSApp.keyWindow,
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
            // Restore session — for now, just create default window
            // Full restore (recreating splits from state) is a future enhancement
            createNewWindow()
        } else {
            sessionManager?.clearSavedState()
            createNewWindow()
        }
    }

    // MARK: - Import Wizard

    private func checkFirstLaunchWizard() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let simpletonDir = appSupport.appendingPathComponent("Simpleton")
        let wizardDoneFile = simpletonDir.appendingPathComponent(".wizard-done")

        guard !FileManager.default.fileExists(atPath: wizardDoneFile.path) else { return }

        let entries = sshConfigWatcher?.concreteEntries ?? []
        guard !entries.isEmpty else {
            // No SSH config — mark wizard as done, skip
            FileManager.default.createFile(atPath: wizardDoneFile.path, contents: nil)
            return
        }

        // Show wizard as sheet on the key window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showImportWizard(entries: entries)
            FileManager.default.createFile(atPath: wizardDoneFile.path, contents: nil)
        }
    }

    private func showImportWizard(entries: [SSHConfigEntry]) {
        guard let window = NSApp.keyWindow else { return }

        let wizardView = ImportWizardView(
            entries: entries,
            onComplete: { [weak self] bookmarks, groups in
                window.endSheet(window.sheets.last ?? window)
                Task {
                    for bookmark in bookmarks {
                        try? await self?.bookmarkStore?.add(bookmark)
                    }
                }
            },
            onSkip: {
                window.endSheet(window.sheets.last ?? window)
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

    // MARK: - Workspaces

    @objc private func saveWorkspace() {
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
        guard let name = sender.representedObject as? String else { return }
        guard let _ = workspaceManager?.load(name: name) else { return }

        // For now, just create a new window (full workspace restore is future enhancement)
        createNewWindow()
    }
}

extension Notification.Name {
    static let simpletonToggleSidebar = Notification.Name("simpletonToggleSidebar")
    static let simpletonShowSearch = Notification.Name("simpletonShowSearch")
    static let simpletonSplitChanged = Notification.Name("simpletonSplitChanged")
}
