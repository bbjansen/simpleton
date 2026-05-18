// Sources/Simpleton/PaneController.swift
import AppKit
import SwiftTerm
import SimpletonCore

/// Owns a single terminal pane — its LocalProcessTerminalView, process lifecycle,
/// and exit/disconnect state. This is the bridge between the logical SplitNode.pane(id)
/// and the actual NSView + PTY process.
final class PaneController: NSObject, LocalProcessTerminalViewDelegate {

    let id: PaneID
    let terminalView: LocalProcessTerminalView
    private(set) var connectionType: ConnectionType
    private(set) var state: PaneState = .connecting

    /// Manages the exit / disconnect / error banner overlay.
    private var bannerManager: BannerManager?

    /// Callback when the pane's title changes (for tab/window title).
    var onTitleChange: ((String) -> Void)?

    /// Callback when the pane's working directory changes.
    var onDirectoryChange: ((String) -> Void)?

    /// Callback when the process exits.
    var onProcessExit: ((PaneController, Int32?) -> Void)?

    /// Callback when this pane gains focus (user clicks it).
    var onFocused: ((PaneController) -> Void)?

    /// Last known working directory (updated via OSC 7 / shell integration).
    private(set) var currentDirectory: String?

    var sshHost: String? {
        guard case .ssh = connectionType else { return nil }
        return sshBookmark?.host
    }
    var sshUser: String? {
        guard case .ssh = connectionType else { return nil }
        return sshBookmark?.user
    }

    /// Stored environment for shell restarts.
    var shellEnvironment: [String]?

    /// Plugin manager reference for firing events.
    var pluginManager: PluginManager?

    /// SSH reconnection state.
    private var sshBookmark: Bookmark?
    private var sshConfig: AppConfig?
    private var reconnectAttempts = 0
    private var reconnectTimer: Timer?
    private var searchBar: ScrollbackSearchBar?

    private var mouseMonitor: Any?

    init(id: PaneID = UUID(), frame: NSRect, connectionType: ConnectionType) {
        self.id = id
        self.connectionType = connectionType
        self.terminalView = LocalProcessTerminalView(frame: frame)
        super.init()
        self.terminalView.processDelegate = self
        self.terminalView.autoresizingMask = [.width, .height]

        // Add drag-and-drop overlay for file paths
        let dropTarget = TerminalDropTarget(terminal: terminalView)
        terminalView.addSubview(dropTarget)

        // Build right-click context menu
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy", action: #selector(contextCopy(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Paste", action: #selector(contextPaste(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Select All", action: #selector(contextSelectAll(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Search Scrollback", action: #selector(contextSearchScrollback(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Clear Scrollback", action: #selector(contextClearScrollback(_:)), keyEquivalent: "")
        terminalView.menu = menu

        // Track when user clicks this terminal pane to update focus
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self else { return event }
            let locationInView = self.terminalView.convert(event.locationInWindow, from: nil)
            if self.terminalView.bounds.contains(locationInView) && event.window === self.terminalView.window {
                self.onFocused?(self)
            }
            return event
        }

        // Set up banner manager with callbacks back into PaneController
        let bm = BannerManager(hostView: terminalView)
        bm.onReopenShell = { [weak self] in
            guard let self = self else { return }
            if case .local(let shell, let dir) = self.connectionType {
                self.restartShell(shell: shell, environment: self.shellEnvironment, workingDirectory: dir)
            } else if case .ssh = self.connectionType {
                self.reconnectSSH()
            }
        }
        bm.onClosePane = { [weak self] in
            guard let self = self else { return }
            NotificationCenter.default.post(name: .simpletonPaneCloseRequested, object: self.id)
        }
        bm.onExplainError = { [weak self] in
            guard let self = self else { return }
            NotificationCenter.default.post(name: .simpletonExplainError, object: self.id)
        }
        bm.onReconnect = { [weak self] in
            guard let self = self else { return }
            self.reconnectAttempts = 0
            self.reconnectSSH()
        }
        bm.onCancelReconnect = { [weak self] in
            guard let self = self else { return }
            self.cancelAutoReconnect()
            self.bannerManager?.showDisconnectedBanner(canReconnect: true)
        }
        self.bannerManager = bm
    }

    deinit {
        reconnectTimer?.invalidate()
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    /// Start a local shell process.
    func startLocalShell(shell: String, environment: [String]? = nil, workingDirectory: String? = nil) {
        self.shellEnvironment = environment
        state = .running
        terminalView.startProcess(
            executable: shell,
            args: ["-l"],
            environment: environment,
            execName: nil,
            currentDirectory: workingDirectory
        )
    }

    /// Restart the shell (after exit, when user clicks "Reopen").
    func restartShell(shell: String, environment: [String]? = nil, workingDirectory: String? = nil) {
        bannerManager?.remove()
        // Ensure any previous process is stopped before starting a new one.
        terminalView.terminate()
        state = .running
        terminalView.startProcess(
            executable: shell,
            args: ["-l"],
            environment: environment,
            execName: nil,
            currentDirectory: workingDirectory
        )
    }

    /// Start an SSH connection from a bookmark.
    func startSSH(bookmark: Bookmark, config: AppConfig) {
        guard let command = SSHManager.buildCommand(from: bookmark, config: config) else {
            bannerManager?.showError(message: "Invalid connection settings for \(bookmark.name)")
            return
        }

        // Kill any existing process — LocalProcess.startProcess silently
        // returns when `running` is true, so we must terminate first.
        terminalView.terminate()

        sshBookmark = bookmark
        sshConfig = config
        connectionType = .ssh(bookmarkID: bookmark.id)
        state = .connecting
        reconnectAttempts = 0

        onTitleChange?(statusTitle(bookmark.name))

        terminalView.startProcess(
            executable: command.executable,
            args: command.arguments,
            environment: command.environment,
            execName: nil,
            currentDirectory: nil
        )

        // Fire plugin event (treat startProcess as authenticated for now —
        // full auth detection requires ConnectionStateTracker which is Phase B)
        pluginManager?.fireEvent(.onSSHAuthenticated, context: [
            "host": bookmark.host,
            "user": bookmark.user ?? "",
            "port": bookmark.port,
            "bookmarkId": bookmark.id.uuidString,
            "bookmarkName": bookmark.name,
        ])
    }

    /// Attempt to reconnect an SSH session.
    func reconnectSSH() {
        guard let bookmark = sshBookmark, let config = sshConfig else { return }
        bannerManager?.remove()
        state = .connecting

        guard let command = SSHManager.buildCommand(from: bookmark, config: config) else { return }

        // Ensure any previous process is stopped before starting a new one.
        terminalView.terminate()

        terminalView.startProcess(
            executable: command.executable,
            args: command.arguments,
            environment: command.environment,
            execName: nil,
            currentDirectory: nil
        )
    }

    /// Start auto-reconnect with exponential backoff.
    private func startAutoReconnect(config: AppConfig) {
        guard config.ssh.autoReconnect,
              reconnectAttempts < config.ssh.maxReconnectAttempts else {
            bannerManager?.showDisconnectedBanner(canReconnect: true)
            return
        }

        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts - 1)), 30.0)

        bannerManager?.showReconnecting(attempt: reconnectAttempts, delay: delay)

        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.reconnectSSH()
        }
    }

    private func cancelAutoReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }

    // MARK: - LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // No action needed — LocalProcessTerminalView handles pty resize internally
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        onTitleChange?(statusTitle(title))
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        if let dir = directory {
            currentDirectory = dir
            onDirectoryChange?(dir)
        }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        let code = exitCode ?? -1
        cancelAutoReconnect()

        if case .ssh = connectionType {
            // SSH session ended
            state = .disconnected
            onProcessExit?(self, exitCode)

            if let bookmark = sshBookmark {
                pluginManager?.fireEvent(.onSSHDisconnected, context: [
                    "host": bookmark.host,
                    "user": bookmark.user ?? "",
                    "port": bookmark.port,
                    "bookmarkId": bookmark.id.uuidString,
                    "exitCode": code,
                ])
            }

            if let config = sshConfig {
                startAutoReconnect(config: config)
            } else {
                bannerManager?.showDisconnectedBanner(canReconnect: true)
            }
        } else {
            // Local shell exited
            state = .exited(code: code)
            onProcessExit?(self, exitCode)
            bannerManager?.showExitBanner(exitCode: code)

            pluginManager?.fireEvent(.onPaneExit, context: [
                "paneId": id.uuidString,
                "exitCode": code,
                "connectionType": "local",
            ])
        }
    }

    // MARK: - Status Title

    /// Prefixes a title with a status emoji reflecting the pane's current state.
    private func statusTitle(_ title: String) -> String {
        let emoji: String
        switch state {
        case .running:
            if case .ssh = connectionType {
                emoji = "\u{1F7E2}" // green circle — running SSH
            } else {
                return title // no prefix for local shells
            }
        case .connecting:
            emoji = "\u{1F7E1}" // yellow circle
        case .disconnected:
            emoji = "\u{1F534}" // red circle
        case .exited:
            emoji = "\u{23F9}\u{FE0F}" // stop button
        case .authRequired:
            emoji = "\u{1F7E1}" // yellow circle
        }
        return "\(emoji) \(title)"
    }

    // MARK: - Context Menu Actions

    @objc private func contextCopy(_ sender: Any?) {
        if let selected = terminalView.getSelection(), !selected.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(selected, forType: .string)
        }
    }

    @objc private func contextPaste(_ sender: Any?) {
        if let text = NSPasteboard.general.string(forType: .string) {
            let bytes = Array(text.utf8)
            terminalView.send(data: bytes[...])
        }
    }

    @objc private func contextSelectAll(_ sender: Any?) {
        terminalView.selectAll()
    }

    @objc private func contextSearchScrollback(_ sender: Any?) {
        showSearch()
    }

    @objc private func contextClearScrollback(_ sender: Any?) {
        // Send escape sequences to clear screen and scrollback buffer
        terminalView.feed(text: "\u{001b}[2J\u{001b}[3J\u{001b}[H")
    }

    // MARK: - Search

    func showSearch() {
        guard searchBar == nil else {
            searchBar?.activate()
            return
        }
        let bar = ScrollbackSearchBar(terminalView: terminalView)
        bar.autoresizingMask = [.width, .minYMargin]
        bar.frame = NSRect(x: 8, y: terminalView.bounds.height - 40, width: terminalView.bounds.width - 16, height: 36)
        bar.onDismiss = { [weak self] in
            self?.hideSearch()
        }
        terminalView.addSubview(bar)
        searchBar = bar
        bar.activate()
    }

    func hideSearch() {
        searchBar?.removeFromSuperview()
        searchBar = nil
        terminalView.window?.makeFirstResponder(terminalView)
    }
}

extension Notification.Name {
    static let simpletonPaneCloseRequested = Notification.Name("simpletonPaneCloseRequested")
    static let simpletonToggleAIChat = Notification.Name("simpletonToggleAIChat")
    static let simpletonRunSkillPicker = Notification.Name("simpletonRunSkillPicker")
    static let simpletonActivateSkillPicker = Notification.Name("simpletonActivateSkillPicker")
    static let simpletonExplainError = Notification.Name("simpletonExplainError")
    static let simpletonShowPreferences = Notification.Name("simpletonShowPreferences")
    static let simpletonTerminalOutput = Notification.Name("simpletonTerminalOutput")
}
