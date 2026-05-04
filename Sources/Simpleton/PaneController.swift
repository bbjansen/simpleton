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

    init(id: PaneID = UUID(), frame: NSRect, connectionType: ConnectionType) {
        self.id = id
        self.connectionType = connectionType
        self.terminalView = LocalProcessTerminalView(frame: frame)
        super.init()
        self.terminalView.processDelegate = self
        self.terminalView.autoresizingMask = [.width, .height]
    }

    /// Start a local shell process.
    func startLocalShell(shell: String, environment: [String]? = nil, workingDirectory: String? = nil) {
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
    func restartShell(shell: String, workingDirectory: String? = nil) {
        removeBanner()
        state = .running
        terminalView.startProcess(
            executable: shell,
            args: ["-l"],
            environment: nil,
            execName: nil,
            currentDirectory: workingDirectory
        )
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
        state = .exited(code: code)
        onProcessExit?(self, exitCode)
        showExitBanner(exitCode: code)
    }

    // MARK: - Exit Banner

    private func showExitBanner(exitCode: Int32) {
        removeBanner()

        let banner = NSView(frame: NSRect(x: 0, y: 0, width: terminalView.bounds.width, height: 40))
        banner.wantsLayer = true
        banner.layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.95).cgColor
        banner.autoresizingMask = [.width, .minYMargin]

        let label = NSTextField(labelWithString: exitCode == 0 ? "Shell exited" : "Shell exited (code \(exitCode))")
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = exitCode == 0 ? .secondaryLabelColor : NSColor(red: 0.95, green: 0.3, blue: 0.3, alpha: 1)
        label.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(label)

        let reopenButton = NSButton(title: "Reopen Shell", target: self, action: #selector(reopenShellClicked))
        reopenButton.bezelStyle = .inline
        reopenButton.font = NSFont.systemFont(ofSize: 11)
        reopenButton.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(reopenButton)

        let closeButton = NSButton(title: "Close Pane", target: self, action: #selector(closePaneClicked))
        closeButton.bezelStyle = .inline
        closeButton.font = NSFont.systemFont(ofSize: 11)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(closeButton)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -12),
            closeButton.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            reopenButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            reopenButton.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
        ])

        banner.frame.origin.y = terminalView.bounds.height - 40
        terminalView.addSubview(banner)
        bannerView = banner
    }

    private func removeBanner() {
        bannerView?.removeFromSuperview()
        bannerView = nil
    }

    @objc private func reopenShellClicked() {
        if case .local(let shell, let dir) = connectionType {
            restartShell(shell: shell, workingDirectory: dir)
        }
    }

    @objc private func closePaneClicked() {
        // In Phase 2, closing the pane terminates the app (single pane).
        // In Phase 3 (window management), this will remove the pane from the split tree.
        NSApp.terminate(nil)
    }
}
