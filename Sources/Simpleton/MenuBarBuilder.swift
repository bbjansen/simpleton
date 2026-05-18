// Sources/Simpleton/MenuBarBuilder.swift
import AppKit

struct MenuBarBuilder {
    static func build(target: AnyObject, workspacesMenuDelegate: NSMenuDelegate) -> (menu: NSMenu, workspacesMenu: NSMenu) {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Simpleton", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: "Check for Updates...", action: #selector(AppDelegate.checkForUpdates), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Preferences...", action: #selector(AppDelegate.showPreferences), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Simpleton", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Window", action: #selector(AppDelegate.createNewWindow), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "New Tab", action: #selector(AppDelegate.newTab), keyEquivalent: "t")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "New Connection...", action: #selector(AppDelegate.showNewConnection), keyEquivalent: "")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Pane", action: #selector(AppDelegate.closePane), keyEquivalent: "w")

        let closeTabItem = NSMenuItem(title: "Close Tab", action: #selector(AppDelegate.closeTab), keyEquivalent: "W")
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
        editMenu.addItem(withTitle: "Clear Terminal", action: #selector(AppDelegate.clearTerminal), keyEquivalent: "k")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Find...", action: #selector(AppDelegate.showScrollbackSearch), keyEquivalent: "f")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Increase Font Size", action: #selector(AppDelegate.increaseFontSize), keyEquivalent: "=")
        viewMenu.addItem(withTitle: "Decrease Font Size", action: #selector(AppDelegate.decreaseFontSize), keyEquivalent: "-")
        viewMenu.addItem(withTitle: "Reset Font Size", action: #selector(AppDelegate.resetFontSize), keyEquivalent: "0")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Split menu
        let splitMenuItem = NSMenuItem()
        let splitMenu = NSMenu(title: "Split")
        splitMenu.addItem(withTitle: "Split Right", action: #selector(AppDelegate.splitRight), keyEquivalent: "d")

        let splitDownItem = NSMenuItem(title: "Split Down", action: #selector(AppDelegate.splitDown), keyEquivalent: "D")
        splitDownItem.keyEquivalentModifierMask = [.command, .shift]
        splitMenu.addItem(splitDownItem)

        splitMenu.addItem(.separator())

        let layoutItem = NSMenuItem(title: "Pick Layout\u{2026}", action: #selector(AppDelegate.pickLayout), keyEquivalent: "L")
        layoutItem.keyEquivalentModifierMask = [.command, .shift]
        splitMenu.addItem(layoutItem)

        splitMenu.addItem(.separator())

        let zoomItem = NSMenuItem(title: "Toggle Fullscreen Pane", action: #selector(AppDelegate.togglePaneZoom), keyEquivalent: "\r")
        zoomItem.keyEquivalentModifierMask = [.command, .shift]
        splitMenu.addItem(zoomItem)

        splitMenu.addItem(.separator())

        // Focus navigation
        let focusLeftItem = NSMenuItem(title: "Focus Left", action: #selector(AppDelegate.focusLeft), keyEquivalent: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)))
        focusLeftItem.keyEquivalentModifierMask = [.command, .option]
        splitMenu.addItem(focusLeftItem)

        let focusRightItem = NSMenuItem(title: "Focus Right", action: #selector(AppDelegate.focusRight), keyEquivalent: String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)))
        focusRightItem.keyEquivalentModifierMask = [.command, .option]
        splitMenu.addItem(focusRightItem)

        let focusUpItem = NSMenuItem(title: "Focus Up", action: #selector(AppDelegate.focusUp), keyEquivalent: String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)))
        focusUpItem.keyEquivalentModifierMask = [.command, .option]
        splitMenu.addItem(focusUpItem)

        let focusDownItem = NSMenuItem(title: "Focus Down", action: #selector(AppDelegate.focusDown), keyEquivalent: String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)))
        focusDownItem.keyEquivalentModifierMask = [.command, .option]
        splitMenu.addItem(focusDownItem)

        splitMenuItem.submenu = splitMenu
        mainMenu.addItem(splitMenuItem)

        // SSH menu
        let sshMenuItem = NSMenuItem()
        let sshMenu = NSMenu(title: "SSH")

        let quickConnectItem = NSMenuItem(title: "Quick Connect...", action: #selector(AppDelegate.showQuickConnect), keyEquivalent: "k")
        sshMenu.addItem(quickConnectItem)

        sshMenu.addItem(withTitle: "New Connection...", action: #selector(AppDelegate.showNewConnection), keyEquivalent: "")

        let toggleSidebarItem = NSMenuItem(title: "Toggle Sidebar", action: #selector(AppDelegate.toggleSidebar), keyEquivalent: "S")
        toggleSidebarItem.keyEquivalentModifierMask = [.command, .shift]
        sshMenu.addItem(toggleSidebarItem)

        sshMenuItem.submenu = sshMenu
        mainMenu.addItem(sshMenuItem)

        // AI menu
        let aiMenuItem = NSMenuItem()
        let aiMenu = NSMenu(title: "AI")
        let chatItem = NSMenuItem(title: "AI Chat", action: #selector(AppDelegate.toggleAIChat), keyEquivalent: "A")
        chatItem.keyEquivalentModifierMask = [.command, .shift]
        aiMenu.addItem(chatItem)
        let skillItem = NSMenuItem(title: "Run Skill\u{2026}", action: #selector(AppDelegate.showSkillPicker), keyEquivalent: "K")
        skillItem.keyEquivalentModifierMask = [.command, .shift]
        aiMenu.addItem(skillItem)
        aiMenu.addItem(withTitle: "AI: Explain Selection", action: #selector(AppDelegate.explainSelection), keyEquivalent: "")
        aiMenu.addItem(withTitle: "AI: Explain Error", action: #selector(AppDelegate.explainLastError), keyEquivalent: "")
        aiMenuItem.submenu = aiMenu
        mainMenu.addItem(aiMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")

        let nextTabItem = NSMenuItem(title: "Next Tab", action: #selector(AppDelegate.nextTab), keyEquivalent: "}")
        nextTabItem.keyEquivalentModifierMask = [.command, .shift]
        windowMenu.addItem(nextTabItem)

        let prevTabItem = NSMenuItem(title: "Previous Tab", action: #selector(AppDelegate.prevTab), keyEquivalent: "{")
        prevTabItem.keyEquivalentModifierMask = [.command, .shift]
        windowMenu.addItem(prevTabItem)

        windowMenu.addItem(.separator())
        let saveWorkspaceItem = NSMenuItem(title: "Save Workspace...", action: #selector(AppDelegate.saveWorkspace), keyEquivalent: "S")
        saveWorkspaceItem.keyEquivalentModifierMask = [.command, .option]
        windowMenu.addItem(saveWorkspaceItem)

        // Workspace submenu (dynamic -- rebuilt each time the menu opens)
        let workspacesItem = NSMenuItem(title: "Workspaces", action: nil, keyEquivalent: "")
        let workspacesMenu = NSMenu(title: "Workspaces")
        workspacesMenu.delegate = workspacesMenuDelegate
        workspacesItem.submenu = workspacesMenu
        windowMenu.addItem(workspacesItem)

        windowMenu.addItem(.separator())
        for i in 1...9 {
            let tabItem = NSMenuItem(title: "Tab \(i)", action: #selector(AppDelegate.switchToTabN(_:)), keyEquivalent: String(i))
            tabItem.tag = i
            windowMenu.addItem(tabItem)
        }

        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        // Help menu
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        let paletteItem = NSMenuItem(title: "Command Palette...", action: #selector(AppDelegate.showCommandPalette), keyEquivalent: "P")
        paletteItem.keyEquivalentModifierMask = [.command, .shift]
        helpMenu.addItem(paletteItem)
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu

        return (menu: mainMenu, workspacesMenu: workspacesMenu)
    }
}
