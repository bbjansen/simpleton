// Sources/Simpleton/TabContainerController.swift
import AppKit
import SimpletonCore

/// View controller for one tab's content. Owns a SplitController and manages
/// creating new panes when splits are requested.
final class TabContainerController: NSViewController {

    let splitController: SplitController
    private let config: AppConfig
    private let theme: Theme
    private var closeObserver: NSObjectProtocol?
    private var sidebarToggleObserver: NSObjectProtocol?
    private var searchObserver: NSObjectProtocol?

    /// The outer NSSplitView: sidebar | terminal content
    private var outerSplitView: NSSplitView?
    private var sidebarHostController: SidebarHostController?
    private var isSidebarVisible = false

    /// Reference to the bookmark store for frecency updates.
    var bookmarkStore: BookmarkStore? {
        didSet { setupSidebar() }
    }

    /// SSH config watcher reference.
    var sshConfigWatcher: SSHConfigWatcher? {
        didSet { setupSidebar() }
    }

    init(config: AppConfig, theme: Theme) {
        self.config = config
        self.theme = theme

        // Create the initial pane
        let shell = ShellDetector.detectShell(config: config)
        let workingDir = ShellDetector.workingDirectory(config: config)
        let initialPane = PaneController(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            connectionType: .local(shell: shell, workingDirectory: workingDir)
        )
        ThemeApplier.apply(theme: theme, config: config, to: initialPane.terminalView)

        self.splitController = SplitController(initialPaneController: initialPane)
        super.init(nibName: nil, bundle: nil)

        // Configure pane factory for future splits
        splitController.paneFactory = { [weak self] paneID in
            self?.createPane(id: paneID) ?? PaneController(id: paneID, frame: .zero, connectionType: .local(shell: "/bin/zsh", workingDirectory: NSHomeDirectory()))
        }

        // Observe pane close requests
        closeObserver = NotificationCenter.default.addObserver(
            forName: .simpletonPaneCloseRequested,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let paneID = notification.object as? PaneID,
                  let self = self,
                  self.splitController.panes[paneID] != nil else { return }
            self.splitController.closePane(paneID)
        }

        // Observe sidebar toggle
        sidebarToggleObserver = NotificationCenter.default.addObserver(
            forName: .simpletonToggleSidebar,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.toggleSidebar()
        }

        // Observe search requests
        searchObserver = NotificationCenter.default.addObserver(
            forName: .simpletonShowSearch,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self,
                  let pane = self.splitController.panes[self.splitController.focusedPaneID] else { return }
            pane.showSearch()
        }

        // Start the initial shell
        let env = buildEnvironment()
        initialPane.startLocalShell(shell: shell, environment: env, workingDirectory: workingDir)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = sidebarToggleObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = searchObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func loadView() {
        let frame = NSRect(x: 0, y: 0, width: 800, height: 600)

        // Outer split view: sidebar | terminal content
        let outer = NSSplitView(frame: frame)
        outer.isVertical = true
        outer.dividerStyle = .thin
        outer.autoresizingMask = [.width, .height]
        outerSplitView = outer

        // Terminal content (always present)
        splitController.rootView.frame = frame
        splitController.rootView.autoresizingMask = [.width, .height]
        outer.addSubview(splitController.rootView)

        self.view = outer
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        splitController.setFocus(to: splitController.focusedPaneID)
    }

    // MARK: - Sidebar

    private func setupSidebar() {
        guard let store = bookmarkStore else { return }

        // Recreate the host controller when dependencies change (e.g. sshConfigWatcher
        // was nil on the first call but is now available). If the sidebar is currently
        // visible, swap the view in the outer split view.
        let wasVisible = isSidebarVisible
        if let oldHost = sidebarHostController, wasVisible {
            oldHost.view.removeFromSuperview()
            oldHost.removeFromParent()
            isSidebarVisible = false
        }

        let host = SidebarHostController(
            bookmarkStore: store,
            sshConfigWatcher: sshConfigWatcher,
            config: config
        )
        host.onConnect = { [weak self] bookmark in
            self?.openSSHConnection(bookmark: bookmark)
        }
        host.onNewConnection = { [weak self] in
            guard let window = self?.view.window else { return }
            NotificationCenter.default.post(name: .simpletonShowNewConnection, object: window)
        }
        sidebarHostController = host

        // If the sidebar was showing before the rebuild, re-show it.
        if wasVisible {
            toggleSidebar()
        }
    }

    func toggleSidebar() {
        guard let outer = outerSplitView else { return }

        if isSidebarVisible {
            // Hide sidebar — remove as child view controller and from split view
            if let host = sidebarHostController {
                host.view.removeFromSuperview()
                host.removeFromParent()
            }
            isSidebarVisible = false
        } else {
            // Show sidebar
            setupSidebar()
            guard let host = sidebarHostController else { return }
            // Add as child view controller so the NSHostingView participates
            // in the responder chain and receives mouse events correctly.
            addChild(host)
            host.view.frame = NSRect(x: 0, y: 0, width: 240, height: outer.bounds.height)
            outer.insertArrangedSubview(host.view, at: 0)
            outer.setPosition(240, ofDividerAt: 0)
            isSidebarVisible = true
        }

        // Refocus terminal
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.splitController.setFocus(to: self.splitController.focusedPaneID)
        }
    }

    // MARK: - Pane Factory

    private func createPane(id: PaneID) -> PaneController {
        let shell = ShellDetector.detectShell(config: config)
        let workingDir = ShellDetector.workingDirectory(config: config)
        let pane = PaneController(
            id: id,
            frame: NSRect(x: 0, y: 0, width: 400, height: 300),
            connectionType: .local(shell: shell, workingDirectory: workingDir)
        )
        ThemeApplier.apply(theme: theme, config: config, to: pane.terminalView)

        let env = buildEnvironment()
        pane.startLocalShell(shell: shell, environment: env, workingDirectory: workingDir)

        pane.onTitleChange = { [weak self] title in
            self?.view.window?.tab.title = title
        }

        return pane
    }

    private func buildEnvironment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = config.general.termVariable
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        return env.map { "\($0.key)=\($0.value)" }
    }

    // MARK: - SSH Connections

    /// Open an SSH connection in a new split pane or the current pane.
    func openSSHConnection(bookmark: Bookmark, inNewSplit direction: SplitDirection? = nil) {
        if let direction = direction {
            // Temporarily override the pane factory to create an SSH pane
            let previousFactory = splitController.paneFactory
            splitController.paneFactory = { [weak self] paneID in
                guard let self = self else {
                    return PaneController(id: paneID, frame: .zero, connectionType: .ssh(bookmarkID: bookmark.id))
                }
                return self.createSSHPane(id: paneID, bookmark: bookmark)
            }
            splitController.splitFocusedPane(direction: direction)
            // Restore original factory
            splitController.paneFactory = previousFactory
        } else {
            // Open in current focused pane — start SSH in existing pane
            if let pane = splitController.panes[splitController.focusedPaneID] {
                pane.startSSH(bookmark: bookmark, config: config)
            }
        }

        // Record frecency
        Task {
            await bookmarkStore?.recordUse(bookmarkId: bookmark.id)
        }
    }

    private func createSSHPane(id: PaneID, bookmark: Bookmark) -> PaneController {
        let pane = PaneController(
            id: id,
            frame: NSRect(x: 0, y: 0, width: 400, height: 300),
            connectionType: .ssh(bookmarkID: bookmark.id)
        )
        ThemeApplier.apply(theme: theme, config: config, to: pane.terminalView)
        pane.startSSH(bookmark: bookmark, config: config)

        pane.onTitleChange = { [weak self] title in
            self?.view.window?.tab.title = title
        }

        return pane
    }
}
