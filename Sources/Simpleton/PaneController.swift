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

    /// Banner view shown when process exits or disconnects.
    private var bannerView: NSView?

    /// Callback when the pane's title changes (for tab/window title).
    var onTitleChange: ((String) -> Void)?

    /// Callback when the pane's working directory changes.
    var onDirectoryChange: ((String) -> Void)?

    /// Callback when the process exits.
    var onProcessExit: ((PaneController, Int32?) -> Void)?

    /// Stored environment for shell restarts.
    var shellEnvironment: [String]?

    /// SSH reconnection state.
    private var sshBookmark: Bookmark?
    private var sshConfig: AppConfig?
    private var reconnectAttempts = 0
    private var reconnectTimer: Timer?
    private var searchBar: ScrollbackSearchBar?

    init(id: PaneID = UUID(), frame: NSRect, connectionType: ConnectionType) {
        self.id = id
        self.connectionType = connectionType
        self.terminalView = LocalProcessTerminalView(frame: frame)
        super.init()
        self.terminalView.processDelegate = self
        self.terminalView.autoresizingMask = [.width, .height]
    }

    deinit {
        reconnectTimer?.invalidate()
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
        removeBanner()
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
            showErrorBanner(message: "Invalid connection settings for \(bookmark.name)")
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

        terminalView.startProcess(
            executable: command.executable,
            args: command.arguments,
            environment: command.environment,
            execName: nil,
            currentDirectory: nil
        )
    }

    /// Attempt to reconnect an SSH session.
    func reconnectSSH() {
        guard let bookmark = sshBookmark, let config = sshConfig else { return }
        removeBanner()
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
            showDisconnectedBanner(canReconnect: true)
            return
        }

        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts - 1)), 30.0)

        showReconnectingBanner(attempt: reconnectAttempts, delay: delay)

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
        onTitleChange?(title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        if let dir = directory {
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
            if let config = sshConfig {
                startAutoReconnect(config: config)
            } else {
                showDisconnectedBanner(canReconnect: true)
            }
        } else {
            // Local shell exited
            state = .exited(code: code)
            onProcessExit?(self, exitCode)
            showExitBanner(exitCode: code)
        }
    }

    // MARK: - Exit Banner

    private func showExitBanner(exitCode: Int32) {
        removeBanner()

        let isCleanExit = exitCode == 0
        let tintColor = isCleanExit
            ? NSColor(red: 0.3, green: 0.8, blue: 0.5, alpha: 1)
            : NSColor(red: 0.95, green: 0.35, blue: 0.35, alpha: 1)
        let bgColor = isCleanExit
            ? NSColor(red: 0.15, green: 0.22, blue: 0.17, alpha: 0.95)
            : NSColor(red: 0.25, green: 0.13, blue: 0.13, alpha: 0.95)
        let borderColor = isCleanExit
            ? NSColor(red: 0.3, green: 0.8, blue: 0.5, alpha: 0.3)
            : NSColor(red: 0.95, green: 0.35, blue: 0.35, alpha: 0.3)

        let banner = NSView(frame: NSRect(x: 8, y: 0, width: terminalView.bounds.width - 16, height: 44))
        banner.wantsLayer = true
        banner.layer?.backgroundColor = bgColor.cgColor
        banner.layer?.cornerRadius = 8
        banner.layer?.borderWidth = 1
        banner.layer?.borderColor = borderColor.cgColor
        banner.autoresizingMask = [.width, .minYMargin]

        let iconName = isCleanExit ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        let icon = NSImageView(image: NSImage(systemSymbolName: iconName, accessibilityDescription: nil)!)
        icon.contentTintColor = tintColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setContentHuggingPriority(.required, for: .horizontal)
        banner.addSubview(icon)

        let label = NSTextField(labelWithString: isCleanExit ? "Shell exited" : "Shell exited (code \(exitCode))")
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = tintColor
        label.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(label)

        let reopenButton = NSButton(title: "Reopen Shell", target: self, action: #selector(reopenShellClicked))
        reopenButton.bezelStyle = .inline
        reopenButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        reopenButton.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(reopenButton)

        let closeButton = NSButton(title: "Close Pane", target: self, action: #selector(closePaneClicked))
        closeButton.bezelStyle = .inline
        closeButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(closeButton)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -14),
            closeButton.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            reopenButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            reopenButton.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
        ])

        banner.frame.origin.y = terminalView.bounds.height - 52
        terminalView.addSubview(banner)
        bannerView = banner
    }

    private func removeBanner() {
        bannerView?.removeFromSuperview()
        bannerView = nil
    }

    @objc private func reopenShellClicked() {
        if case .local(let shell, let dir) = connectionType {
            restartShell(shell: shell, environment: shellEnvironment, workingDirectory: dir)
        } else if case .ssh = connectionType {
            reconnectSSH()
        }
    }

    @objc private func closePaneClicked() {
        // Find the SplitController that owns this pane by walking up the responder chain
        // For now, post a notification that the TabContainerController can handle
        NotificationCenter.default.post(name: .simpletonPaneCloseRequested, object: self.id)
    }

    // MARK: - SSH Banners

    private func showDisconnectedBanner(canReconnect: Bool) {
        removeBanner()

        let tintColor = NSColor(red: 0.95, green: 0.7, blue: 0.2, alpha: 1)
        let bgColor = NSColor(red: 0.25, green: 0.2, blue: 0.1, alpha: 0.95)
        let borderColor = NSColor(red: 0.95, green: 0.7, blue: 0.2, alpha: 0.25)

        let banner = NSView(frame: NSRect(x: 8, y: 0, width: terminalView.bounds.width - 16, height: 44))
        banner.wantsLayer = true
        banner.layer?.backgroundColor = bgColor.cgColor
        banner.layer?.cornerRadius = 8
        banner.layer?.borderWidth = 1
        banner.layer?.borderColor = borderColor.cgColor
        banner.autoresizingMask = [.width, .minYMargin]

        let icon = NSImageView(image: NSImage(systemSymbolName: "wifi.slash", accessibilityDescription: nil)!)
        icon.contentTintColor = tintColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setContentHuggingPriority(.required, for: .horizontal)
        banner.addSubview(icon)

        let label = NSTextField(labelWithString: "Disconnected")
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = tintColor
        label.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(label)

        if canReconnect {
            let reconnectButton = NSButton(title: "Reconnect", target: self, action: #selector(reconnectClicked))
            reconnectButton.bezelStyle = .inline
            reconnectButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            reconnectButton.translatesAutoresizingMaskIntoConstraints = false
            banner.addSubview(reconnectButton)

            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 14),
                icon.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 16),
                icon.heightAnchor.constraint(equalToConstant: 16),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
                label.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
                reconnectButton.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -14),
                reconnectButton.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 14),
                icon.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 16),
                icon.heightAnchor.constraint(equalToConstant: 16),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
                label.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            ])
        }

        banner.frame.origin.y = terminalView.bounds.height - 52
        terminalView.addSubview(banner)
        bannerView = banner
    }

    private func showReconnectingBanner(attempt: Int, delay: Double) {
        removeBanner()

        let tintColor = NSColor(red: 0.45, green: 0.65, blue: 1.0, alpha: 1)
        let bgColor = NSColor(red: 0.12, green: 0.15, blue: 0.25, alpha: 0.95)
        let borderColor = NSColor(red: 0.45, green: 0.65, blue: 1.0, alpha: 0.25)

        let banner = NSView(frame: NSRect(x: 8, y: 0, width: terminalView.bounds.width - 16, height: 44))
        banner.wantsLayer = true
        banner.layer?.backgroundColor = bgColor.cgColor
        banner.layer?.cornerRadius = 8
        banner.layer?.borderWidth = 1
        banner.layer?.borderColor = borderColor.cgColor
        banner.autoresizingMask = [.width, .minYMargin]

        let icon = NSImageView(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)!)
        icon.contentTintColor = tintColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setContentHuggingPriority(.required, for: .horizontal)
        banner.addSubview(icon)

        let label = NSTextField(labelWithString: "Reconnecting (attempt \(attempt))...")
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = tintColor
        label.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(label)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelReconnectClicked))
        cancelButton.bezelStyle = .inline
        cancelButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -14),
            cancelButton.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
        ])

        banner.frame.origin.y = terminalView.bounds.height - 52
        terminalView.addSubview(banner)
        bannerView = banner
    }

    private func showErrorBanner(message: String) {
        removeBanner()

        let tintColor = NSColor(red: 0.95, green: 0.35, blue: 0.35, alpha: 1)
        let bgColor = NSColor(red: 0.25, green: 0.13, blue: 0.13, alpha: 0.95)
        let borderColor = NSColor(red: 0.95, green: 0.35, blue: 0.35, alpha: 0.25)

        let banner = NSView(frame: NSRect(x: 8, y: 0, width: terminalView.bounds.width - 16, height: 44))
        banner.wantsLayer = true
        banner.layer?.backgroundColor = bgColor.cgColor
        banner.layer?.cornerRadius = 8
        banner.layer?.borderWidth = 1
        banner.layer?.borderColor = borderColor.cgColor
        banner.autoresizingMask = [.width, .minYMargin]

        let icon = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)!)
        icon.contentTintColor = tintColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setContentHuggingPriority(.required, for: .horizontal)
        banner.addSubview(icon)

        let label = NSTextField(labelWithString: message)
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = tintColor
        label.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(label)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
        ])

        banner.frame.origin.y = terminalView.bounds.height - 52
        terminalView.addSubview(banner)
        bannerView = banner
    }

    @objc private func reconnectClicked() {
        reconnectAttempts = 0
        reconnectSSH()
    }

    @objc private func cancelReconnectClicked() {
        cancelAutoReconnect()
        showDisconnectedBanner(canReconnect: true)
    }

    // MARK: - Search

    func showSearch() {
        guard searchBar == nil else {
            searchBar?.activate()
            return
        }
        let bar = ScrollbackSearchBar(terminalView: terminalView)
        bar.autoresizingMask = [.width, .minYMargin]
        bar.frame = NSRect(x: 0, y: terminalView.bounds.height - 32, width: terminalView.bounds.width, height: 32)
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
}
