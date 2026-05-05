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

    /// Reference to the bookmark store for frecency updates.
    var bookmarkStore: BookmarkStore?

    /// SSH config watcher reference.
    var sshConfigWatcher: SSHConfigWatcher?

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

        // Start the initial shell
        let env = buildEnvironment()
        initialPane.startLocalShell(shell: shell, environment: env, workingDirectory: workingDir)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        container.autoresizingMask = [.width, .height]

        splitController.rootView.frame = container.bounds
        splitController.rootView.autoresizingMask = [.width, .height]
        container.addSubview(splitController.rootView)

        self.view = container
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        splitController.setFocus(to: splitController.focusedPaneID)
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
