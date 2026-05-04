// Sources/Simpleton/AppDelegate.swift
import AppKit
import SwiftTerm
import SimpletonCore

class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: NSWindow!
    private var paneController: PaneController!
    private var config: AppConfig = AppConfig()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        // Load config (synchronous for startup — config is tiny)
        loadConfig()

        // Create window
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Simpleton"
        window.minSize = NSSize(width: 400, height: 300)
        window.center()
        window.tabbingMode = .preferred

        // Detect shell and working directory
        let shell = ShellDetector.detectShell(config: config)
        let workingDir = ShellDetector.workingDirectory(config: config)

        // Create pane controller
        let contentFrame = window.contentView!.bounds
        paneController = PaneController(
            frame: contentFrame,
            connectionType: .local(shell: shell, workingDirectory: workingDir)
        )

        // Apply theme
        let theme = Theme(name: "default-dark")
        ThemeApplier.apply(theme: theme, config: config, to: paneController.terminalView)

        // Wire up title changes
        paneController.onTitleChange = { [weak self] title in
            self?.window.title = title
        }

        // Add terminal view to window
        window.contentView!.addSubview(paneController.terminalView)

        // Set TERM environment variable
        let termEnv = buildEnvironment()

        // Start shell
        paneController.startLocalShell(
            shell: shell,
            environment: termEnv,
            workingDirectory: workingDir
        )

        // Show window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Make terminal view first responder (capture keyboard input)
        window.makeFirstResponder(paneController.terminalView)

        // Build basic menu bar
        buildMenuBar()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // MARK: - Config

    private func loadConfig() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let simpletonDir = appSupport.appendingPathComponent("Simpleton")
        let configStore = ConfigStore(directory: simpletonDir)

        // Run synchronously for startup
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                self.config = try await configStore.load()
            } catch {
                self.config = AppConfig()
            }
            semaphore.signal()
        }
        semaphore.wait()
    }

    // MARK: - Environment

    private func buildEnvironment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = config.general.termVariable
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        return env.map { "\($0.key)=\($0.value)" }
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

        // Edit menu (for copy/paste to work)
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

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Font size actions

    @objc private func increaseFontSize() {
        let currentSize = paneController.terminalView.font.pointSize
        paneController.terminalView.font = paneController.terminalView.font.withSize(currentSize + 1)
    }

    @objc private func decreaseFontSize() {
        let currentSize = paneController.terminalView.font.pointSize
        if currentSize > 8 {
            paneController.terminalView.font = paneController.terminalView.font.withSize(currentSize - 1)
        }
    }

    @objc private func resetFontSize() {
        let defaultSize = CGFloat(config.appearance.fontSize)
        paneController.terminalView.font = paneController.terminalView.font.withSize(defaultSize)
    }
}
