// Sources/Simpleton/Views/PreferencesWindow.swift
import AppKit
import SwiftUI
import SimpletonCore

/// Manages the preferences window (Cmd+,).
final class PreferencesWindowController {

    private var window: NSWindow?
    private var config: AppConfig
    private var onConfigChanged: ((AppConfig) -> Void)?

    init(config: AppConfig, onConfigChanged: @escaping (AppConfig) -> Void) {
        self.config = config
        self.onConfigChanged = onConfigChanged
    }

    func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let prefsView = PreferencesView(config: config) { [weak self] newConfig in
            self?.config = newConfig
            self?.onConfigChanged?(newConfig)
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.contentView = NSHostingView(rootView: prefsView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            self?.window = nil
        }
    }
}

// MARK: - SwiftUI Preferences

struct PreferencesView: View {
    @State var config: AppConfig
    let onChanged: (AppConfig) -> Void

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralTab(config: $config, onChanged: onChanged).tabItem { Label("General", systemImage: "gear") }.tag(0)
            AppearanceTab(config: $config, onChanged: onChanged).tabItem { Label("Appearance", systemImage: "paintbrush") }.tag(1)
            TerminalTab(config: $config, onChanged: onChanged).tabItem { Label("Terminal", systemImage: "terminal") }.tag(2)
            SSHPrefsTab(config: $config, onChanged: onChanged).tabItem { Label("SSH", systemImage: "network") }.tag(3)
            KeysTab().tabItem { Label("Keys", systemImage: "keyboard") }.tag(4)
        }
        .padding(20)
        .frame(width: 560, height: 480)
    }
}

struct GeneralTab: View {
    @Binding var config: AppConfig
    let onChanged: (AppConfig) -> Void

    var body: some View {
        Form {
            Section("Shell") {
                TextField("Shell path", text: $config.general.shell)
                    .onChange(of: config.general.shell) { _ in onChanged(config) }
                Text("Path to the shell executable (e.g. /bin/zsh)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Detection", selection: $config.general.shellDetection) {
                    Text("Environment ($SHELL)").tag(ShellDetection.environment)
                    Text("Directory Services (dscl)").tag(ShellDetection.dscl)
                }
                .onChange(of: config.general.shellDetection) { _ in onChanged(config) }
                Text("How to detect the default shell when the path above is empty")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Startup") {
                Toggle("Restore previous session", isOn: $config.general.restorePreviousSession)
                    .onChange(of: config.general.restorePreviousSession) { _ in onChanged(config) }
                Text("Re-open tabs and connections from your last session")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Toggle("Confirm before closing", isOn: $config.general.confirmBeforeClosing)
                    .onChange(of: config.general.confirmBeforeClosing) { _ in onChanged(config) }
            }

            Section("Terminal") {
                TextField("TERM variable", text: $config.general.termVariable)
                    .onChange(of: config.general.termVariable) { _ in onChanged(config) }
                Text("The TERM environment variable sent to remote hosts (default: xterm-256color)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct AppearanceTab: View {
    @Binding var config: AppConfig
    let onChanged: (AppConfig) -> Void

    var body: some View {
        Form {
            Section("Font") {
                TextField("Font family", text: $config.appearance.fontFamily)
                    .onChange(of: config.appearance.fontFamily) { _ in onChanged(config) }
                Text("Use a monospaced font for best results (e.g. SF Mono, Menlo, JetBrains Mono)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Stepper("Size: \(config.appearance.fontSize)", value: $config.appearance.fontSize, in: 8...32)
                    .onChange(of: config.appearance.fontSize) { _ in onChanged(config) }
            }

            Section("Cursor") {
                Picker("Style", selection: $config.appearance.cursorStyle) {
                    Text("Block").tag(CursorStyle.block)
                    Text("Beam").tag(CursorStyle.beam)
                    Text("Underline").tag(CursorStyle.underline)
                }
                .onChange(of: config.appearance.cursorStyle) { _ in onChanged(config) }
                Toggle("Blink cursor", isOn: $config.appearance.cursorBlink)
                    .onChange(of: config.appearance.cursorBlink) { _ in onChanged(config) }
            }

            Section("Window") {
                Slider(value: $config.appearance.windowOpacity, in: 0.5...1.0, step: 0.05) {
                    Text("Opacity: \(config.appearance.windowOpacity, specifier: "%.0f%%")")
                }
                .onChange(of: config.appearance.windowOpacity) { _ in onChanged(config) }
                Text("Lower values create a translucent terminal window")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Toggle("Thin strokes (non-Retina)", isOn: $config.appearance.thinStrokes)
                    .onChange(of: config.appearance.thinStrokes) { _ in onChanged(config) }
            }
        }
        .formStyle(.grouped)
    }
}

struct TerminalTab: View {
    @Binding var config: AppConfig
    let onChanged: (AppConfig) -> Void

    var body: some View {
        Form {
            Section("Scrollback") {
                Stepper("Lines: \(config.terminal.scrollbackLines)", value: $config.terminal.scrollbackLines, in: 1000...100000, step: 1000)
                    .onChange(of: config.terminal.scrollbackLines) { _ in onChanged(config) }
                Text("Number of lines to keep in the scrollback buffer")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Clipboard") {
                Toggle("Copy on select", isOn: $config.terminal.copyOnSelect)
                    .onChange(of: config.terminal.copyOnSelect) { _ in onChanged(config) }
                Text("Automatically copy selected text to the clipboard")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Toggle("Paste on right-click", isOn: $config.terminal.pasteOnRightClick)
                    .onChange(of: config.terminal.pasteOnRightClick) { _ in onChanged(config) }
            }

            Section("Behavior") {
                Picker("Bell", selection: $config.terminal.bellBehavior) {
                    Text("Visual").tag(BellBehavior.visual)
                    Text("Audio").tag(BellBehavior.audio)
                    Text("None").tag(BellBehavior.none)
                }
                .onChange(of: config.terminal.bellBehavior) { _ in onChanged(config) }
                Toggle("Mouse reporting", isOn: $config.terminal.mouseReporting)
                    .onChange(of: config.terminal.mouseReporting) { _ in onChanged(config) }
                Text("Forward mouse events to terminal applications (e.g. vim, tmux)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Toggle("Close pane on clean exit", isOn: $config.terminal.closeOnCleanExit)
                    .onChange(of: config.terminal.closeOnCleanExit) { _ in onChanged(config) }
                Text("Automatically close the pane when the shell exits with code 0")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct SSHPrefsTab: View {
    @Binding var config: AppConfig
    let onChanged: (AppConfig) -> Void

    var body: some View {
        Form {
            Section("Defaults") {
                TextField("Default user", text: Binding(
                    get: { config.ssh.defaultUser ?? "" },
                    set: { config.ssh.defaultUser = $0.isEmpty ? nil : $0 }
                ))
                .onChange(of: config.ssh.defaultUser) { _ in onChanged(config) }
                Text("Username to use when none is specified in the connection")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Connection") {
                Stepper("Keepalive: \(config.ssh.keepaliveInterval)s", value: $config.ssh.keepaliveInterval, in: 0...300, step: 10)
                    .onChange(of: config.ssh.keepaliveInterval) { _ in onChanged(config) }
                Text("Interval in seconds between keepalive packets (0 to disable)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Toggle("Auto-reconnect", isOn: $config.ssh.autoReconnect)
                    .onChange(of: config.ssh.autoReconnect) { _ in onChanged(config) }
                Stepper("Max reconnect attempts: \(config.ssh.maxReconnectAttempts)", value: $config.ssh.maxReconnectAttempts, in: 1...50)
                    .onChange(of: config.ssh.maxReconnectAttempts) { _ in onChanged(config) }
            }

            Section("Forwarding") {
                Toggle("Agent forwarding", isOn: $config.ssh.agentForwarding)
                    .onChange(of: config.ssh.agentForwarding) { _ in onChanged(config) }
                Text("Forward the local SSH agent to remote hosts")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Toggle("X11 forwarding", isOn: $config.ssh.x11Forwarding)
                    .onChange(of: config.ssh.x11Forwarding) { _ in onChanged(config) }
                Toggle("ControlMaster multiplexing", isOn: $config.ssh.controlMaster)
                    .onChange(of: config.ssh.controlMaster) { _ in onChanged(config) }
                Text("Share a single TCP connection across multiple SSH sessions to the same host")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct KeysTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "keyboard")
                .font(.system(size: 28))
                .foregroundColor(Color.white.opacity(0.15))
            Text("Keyboard shortcuts are configured in the menu bar.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Text("Custom key bindings will be available in a future update.")
                .font(.caption)
                .foregroundColor(Color.secondary.opacity(0.7))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
