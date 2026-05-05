// Sources/Simpleton/AppDelegate.swift
import AppKit
import SwiftTerm
import SimpletonCore

class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowControllers: [WindowController] = []
    private var config: AppConfig = AppConfig()
    private var theme: Theme = Theme(name: "default-dark")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        loadConfig()
        createNewWindow()
        buildMenuBar()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowClosed(_:)),
            name: .simpletonWindowClosed,
            object: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
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

    // MARK: - Menu Bar

    private func buildMenuBar() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Simpleton", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
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

        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

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
        guard let window = NSApp.keyWindow else { return }
        let alert = NSAlert()
        alert.messageText = "Pick Layout"
        alert.informativeText = "Choose a layout for this tab."
        for layout in PredefinedLayouts.all {
            alert.addButton(withTitle: layout.name)
        }
        alert.addButton(withTitle: "Cancel")

        alert.beginSheetModal(for: window) { [weak self] response in
            let index = Int(response.rawValue) - Int(NSApplication.ModalResponse.alertFirstButtonReturn.rawValue)
            guard index >= 0, index < PredefinedLayouts.all.count else { return }
            let layout = PredefinedLayouts.all[index]
            self?.activeSplitController?.applyLayout(layout)
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
}
