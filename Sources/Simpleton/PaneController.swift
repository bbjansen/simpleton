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

    /// Callback when this pane gains focus (user clicks it).
    var onFocused: ((PaneController) -> Void)?

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

        // Track when user clicks this terminal pane to update focus
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self else { return event }
            let locationInView = self.terminalView.convert(event.locationInWindow, from: nil)
            if self.terminalView.bounds.contains(locationInView) && event.window === self.terminalView.window {
                self.onFocused?(self)
            }
            return event
        }
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

    // MARK: - Banner Helpers

    /// Creates a standard banner container with the premium dark theme styling.
    private func makeBannerContainer() -> NSVisualEffectView {
        let inset = DT.Banner.inset
        let banner = NSVisualEffectView(frame: NSRect(
            x: inset,
            y: 0,
            width: terminalView.bounds.width - inset * 2,
            height: DT.Banner.height
        ))
        banner.material = .hudWindow
        banner.blendingMode = .behindWindow
        banner.state = .active
        banner.wantsLayer = true
        banner.layer?.cornerRadius = DT.Banner.cornerRadius
        banner.layer?.masksToBounds = true
        banner.layer?.borderWidth = DT.Banner.borderWidth
        banner.autoresizingMask = [.width, .minYMargin]
        return banner
    }

    private func makeIcon(symbolName: String, tintColor: NSColor) -> NSImageView {
        let icon = NSImageView(image: NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)!)
        icon.contentTintColor = tintColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: DT.Banner.iconSize, weight: .medium)
        return icon
    }

    private func makeLabel(text: String, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func makeButton(title: String, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .inline
        button.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func positionAndAddBanner(_ banner: NSView) {
        banner.frame.origin.y = terminalView.bounds.height - DT.Banner.height - DT.Banner.inset
        terminalView.addSubview(banner)
        bannerView = banner
    }

    // MARK: - Exit Banner

    private func showExitBanner(exitCode: Int32) {
        removeBanner()

        let isCleanExit = exitCode == 0
        let tintColor = isCleanExit ? DT.Banner.successTint : DT.Banner.errorTint
        let borderColor = isCleanExit ? DT.Banner.successBorder : DT.Banner.errorBorder

        let banner = makeBannerContainer()
        banner.layer?.borderColor = borderColor.cgColor

        let iconName = isCleanExit ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        let icon = makeIcon(symbolName: iconName, tintColor: tintColor)
        banner.addSubview(icon)

        let label = makeLabel(
            text: isCleanExit ? "Shell exited" : "Shell exited (code \(exitCode))",
            color: tintColor
        )
        banner.addSubview(label)

        let reopenButton = makeButton(title: "Reopen Shell", target: self, action: #selector(reopenShellClicked))
        banner.addSubview(reopenButton)

        let closeButton = makeButton(title: "Close Pane", target: self, action: #selector(closePaneClicked))
        banner.addSubview(closeButton)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: DT.Banner.iconSize),
            icon.heightAnchor.constraint(equalToConstant: DT.Banner.iconSize),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -14),
            closeButton.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            reopenButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            reopenButton.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
        ])

        positionAndAddBanner(banner)
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

        let banner = makeBannerContainer()
        banner.layer?.borderColor = DT.Banner.warningBorder.cgColor

        let icon = makeIcon(symbolName: "wifi.slash", tintColor: DT.Banner.warningTint)
        banner.addSubview(icon)

        let label = makeLabel(text: "Disconnected", color: DT.Banner.warningTint)
        banner.addSubview(label)

        if canReconnect {
            let reconnectButton = makeButton(title: "Reconnect", target: self, action: #selector(reconnectClicked))
            banner.addSubview(reconnectButton)

            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 14),
                icon.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: DT.Banner.iconSize),
                icon.heightAnchor.constraint(equalToConstant: DT.Banner.iconSize),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
                label.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
                reconnectButton.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -14),
                reconnectButton.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 14),
                icon.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: DT.Banner.iconSize),
                icon.heightAnchor.constraint(equalToConstant: DT.Banner.iconSize),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
                label.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            ])
        }

        positionAndAddBanner(banner)
    }

    private func showReconnectingBanner(attempt: Int, delay: Double) {
        removeBanner()

        let banner = makeBannerContainer()
        banner.layer?.borderColor = DT.Banner.infoBorder.cgColor

        let icon = makeIcon(symbolName: "arrow.clockwise", tintColor: DT.Banner.infoTint)
        banner.addSubview(icon)

        let label = makeLabel(text: "Reconnecting (attempt \(attempt))...", color: DT.Banner.infoTint)
        banner.addSubview(label)

        let cancelButton = makeButton(title: "Cancel", target: self, action: #selector(cancelReconnectClicked))
        banner.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: DT.Banner.iconSize),
            icon.heightAnchor.constraint(equalToConstant: DT.Banner.iconSize),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -14),
            cancelButton.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
        ])

        positionAndAddBanner(banner)
    }

    private func showErrorBanner(message: String) {
        removeBanner()

        let banner = makeBannerContainer()
        banner.layer?.borderColor = DT.Banner.errorBorder.cgColor

        let icon = makeIcon(symbolName: "exclamationmark.triangle.fill", tintColor: DT.Banner.errorTint)
        banner.addSubview(icon)

        let label = makeLabel(text: message, color: DT.Banner.errorTint)
        banner.addSubview(label)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: DT.Banner.iconSize),
            icon.heightAnchor.constraint(equalToConstant: DT.Banner.iconSize),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
        ])

        positionAndAddBanner(banner)
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
}
