// Sources/Simpleton/Views/PreferencesWindow.swift
import AppKit
import SimpletonCore
import SwiftUI

/// Manages the preferences window (Cmd+,).
final class PreferencesWindowController {

    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?
    private var config: AppConfig
    private var onConfigChanged: ((AppConfig) -> Void)?
    private var pluginManager: PluginManager?
    private var aiConfig: AIConfig
    private var onAIConfigChanged: ((AIConfig) -> Void)?
    private var skillStore: SkillStore?
    private var panelRegistry: PanelRegistry?

    init(
        config: AppConfig, pluginManager: PluginManager? = nil, aiConfig: AIConfig = AIConfig(),
        skillStore: SkillStore? = nil, panelRegistry: PanelRegistry? = nil,
        onConfigChanged: @escaping (AppConfig) -> Void, onAIConfigChanged: ((AIConfig) -> Void)? = nil
    ) {
        self.config = config
        self.pluginManager = pluginManager
        self.aiConfig = aiConfig
        self.skillStore = skillStore
        self.panelRegistry = panelRegistry
        self.onConfigChanged = onConfigChanged
        self.onAIConfigChanged = onAIConfigChanged
    }

    func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let prefsView = PreferencesView(
            config: config, pluginManager: pluginManager, aiConfig: aiConfig, skillStore: skillStore,
            panelRegistry: panelRegistry,
            onChanged: { [weak self] newConfig in
                self?.config = newConfig
                self?.onConfigChanged?(newConfig)
            },
            onAIConfigChanged: { [weak self] newAIConfig in
                self?.aiConfig = newAIConfig
                self?.onAIConfigChanged?(newAIConfig)
            })

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"  // kept (title hidden) so the live-retint loop can find this window
        window.isReleasedWhenClosed = false
        // Dissolved, themed titlebar to match the app chrome: transparent titlebar + hidden title over
        // a themed-surface strip, so the traffic lights float on the theme color and the whole Settings
        // window reads as one themed surface (the nav uses themedGlass, the forms are themed). Kept
        // opaque — unlike the main window's optional translucency — so the settings strip never leaks
        // the desktop, and the content stays below the titlebar so no control sits in the drag region.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = AppTheme.nsAppearance(
            for: config.appearance.appearanceMode, isDark: AppTheme.activeTheme.isDark)
        window.backgroundColor =
            NSColor(hex: AppTheme.activeTheme.chrome.surface) ?? window.backgroundColor
        window.contentMinSize = NSSize(width: 720, height: 460)
        window.contentView = NSHostingView(rootView: prefsView)
        window.center()
        // Remember the size/position the user drags to, across opens and app launches.
        window.setFrameAutosaveName("SimpletonPreferencesWindow")
        window.makeKeyAndOrderFront(nil)
        self.window = window
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            // Remove the observer immediately so it cannot fire again during the
            // delayed teardown, preventing a retain-cycle crash.
            if let obs = self?.closeObserver {
                NotificationCenter.default.removeObserver(obs)
                self?.closeObserver = nil
            }
            // Delay releasing the window reference so AppKit animation blocks that were
            // captured during the close sequence finish before the window is deallocated,
            // preventing EXC_BAD_ACCESS in _NSWindowTransformAnimation / _Block_release.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                self?.window = nil
            }
        }
    }
}

// MARK: - SwiftUI Preferences

struct PreferencesView: View {
    @State var config: AppConfig
    let pluginManager: PluginManager?
    @State var aiConfig: AIConfig
    let skillStore: SkillStore?
    let panelRegistry: PanelRegistry?
    let onChanged: (AppConfig) -> Void
    let onAIConfigChanged: (AIConfig) -> Void

    @State private var selectedTab = 0
    @ObservedObject private var themeSettings = ThemeSettings.shared

    private var tabs: [(id: Int, label: String, icon: String)] {
        var t: [(Int, String, String)] = [
            (0, "General", "gearshape"),
            (1, "Appearance", "paintbrush.pointed"),
            (2, "Terminal", "terminal"),
            (3, "SSH", "network"),
            (4, "Keys", "keyboard"),
        ]
        if pluginManager != nil {
            t.append((5, "Plugins", "puzzlepiece.extension"))
        }
        t.append((6, "AI", "sparkles"))
        t.append((7, "Skills", "bolt"))
        if panelRegistry != nil {
            t.append((8, "Profiles", "person.crop.rectangle.stack"))
        }
        return t
    }

    var body: some View {
        HSplitView {
            // Sidebar navigation
            VStack(spacing: 2) {
                ForEach(tabs, id: \.id) { tab in
                    Button(action: { selectedTab = tab.id }) {
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 13))
                                .frame(width: 20)
                                .foregroundColor(selectedTab == tab.id ? .white : .secondary)
                            Text(tab.label)
                                .font(.system(size: 13))
                                .foregroundColor(selectedTab == tab.id ? .white : .primary)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selectedTab == tab.id ? themeSettings.accent.opacity(0.85) : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings-tab-\(tab.label.lowercased())")
                }
                Spacer()
            }
            .padding(12)
            .frame(minWidth: 160, idealWidth: 190, maxWidth: 240)
            .themedGlass(DT.surface)  // same glass as the main sidebar (picks up gradients too)

            // Content — Skills and Profiles tabs manage their own scroll/split layout so
            // they must live outside the outer ScrollView.
            if selectedTab == 7, let store = skillStore {
                SkillsPreferencesTab(skillStore: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selectedTab == 8, let registry = panelRegistry {
                ProfilesPreferencesTab(registry: registry)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Group {
                        switch selectedTab {
                        case 0: GeneralTab(config: $config, onChanged: onChanged)
                        case 1: AppearanceTab(config: $config, onChanged: onChanged)
                        case 2: TerminalTab(config: $config, onChanged: onChanged)
                        case 3: SSHPrefsTab(config: $config, onChanged: onChanged)
                        case 4: KeysTab()
                        case 5:
                            if let pm = pluginManager {
                                PluginsPreferencesTab(pluginManager: pm)
                            }
                        case 6:
                            AIPreferencesTab(
                                config: aiConfig,
                                onChanged: { newAIConfig in
                                    aiConfig = newAIConfig
                                    onAIConfigChanged(newAIConfig)
                                })
                        default: EmptyView()
                        }
                    }
                    .padding(24)
                }
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 720, maxWidth: .infinity, minHeight: 460, maxHeight: .infinity)
        .background(DT.base)
        .tint(themeSettings.accent)
    }
}

struct GeneralTab: View {
    @Binding var config: AppConfig
    let onChanged: (AppConfig) -> Void

    var body: some View {
        Form {
            Section {
                TextField("Shell path", text: $config.general.shell)
                    .onChange(of: config.general.shell) { onChanged(config) }
                Text("Path to the shell executable (e.g. /bin/zsh)")
                    .font(.system(size: 11))
                    .foregroundColor(DT.textHelp)
                Picker("Detection", selection: $config.general.shellDetection) {
                    Text("Environment ($SHELL)").tag(ShellDetection.environment)
                    Text("Directory Services (dscl)").tag(ShellDetection.dscl)
                }
                .onChange(of: config.general.shellDetection) { onChanged(config) }
                Text("How to detect the default shell when the path above is empty")
                    .font(.system(size: 11))
                    .foregroundColor(DT.textHelp)

                Toggle("Shell integration (zsh & bash)", isOn: $config.general.shellIntegration)
                    .onChange(of: config.general.shellIntegration) { onChanged(config) }
                Text(
                    "Injects OSC 133 markers so Simpleton knows when commands start, end, and fail "
                        + "(enables exit-status feedback). Your existing zsh config is preserved. "
                        + "Restart shells to apply."
                )
                .font(.system(size: 11))
                .foregroundColor(DT.textHelp)
            } header: {
                PrefsSectionHeader(title: "Shell")
            }

            Section {
                Toggle("Restore previous session", isOn: .constant(false))
                    .disabled(true)
                Text("Temporarily disabled while session restore is being reworked")
                    .font(.system(size: 11))
                    .foregroundColor(DT.textHelp)
                Toggle("Confirm before closing", isOn: $config.general.confirmBeforeClosing)
                    .onChange(of: config.general.confirmBeforeClosing) { onChanged(config) }
            } header: {
                PrefsSectionHeader(title: "Startup")
            }

            Section {
                Picker("Check for updates", selection: $config.general.checkForUpdates) {
                    Text("Automatically").tag(UpdateCheckMode.automatic)
                    Text("Manually").tag(UpdateCheckMode.manual)
                    Text("Disabled").tag(UpdateCheckMode.disabled)
                }
                .onChange(of: config.general.checkForUpdates) { onChanged(config) }
                Text("Automatic checks run in the background and notify you when an update is available")
                    .font(.system(size: 11))
                    .foregroundColor(DT.textHelp)
            } header: {
                PrefsSectionHeader(title: "Updates")
            }

            Section {
                TextField("TERM variable", text: $config.general.termVariable)
                    .onChange(of: config.general.termVariable) { onChanged(config) }
                Text("The TERM environment variable sent to remote hosts (default: xterm-256color)")
                    .font(.system(size: 11))
                    .foregroundColor(DT.textHelp)
            } header: {
                PrefsSectionHeader(title: "Terminal")
            }
        }
        .themedGroupedForm()
    }
}

struct AppearanceTab: View {
    @Binding var config: AppConfig
    let onChanged: (AppConfig) -> Void

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $config.appearance.appearanceMode) {
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                    Text("Auto").tag("auto")
                    Divider()
                    ForEach(ThemePalette.all.filter { $0.id != "dark" && $0.id != "light" }) { th in
                        Text(th.name).tag(th.id)
                    }
                }
                .onChange(of: config.appearance.appearanceMode) { onChanged(config) }

                if !AppTheme.isColoredThemeID(config.appearance.appearanceMode) {
                    Picker("Accent color", selection: $config.appearance.accentColor) {
                        ForEach(AccentPalette.options, id: \.id) { opt in
                            (Text(Image(systemName: "circle.fill")).foregroundColor(AccentPalette.color(opt.id))
                                + Text("  " + opt.label))
                                .tag(opt.id)
                        }
                    }
                    .onChange(of: config.appearance.accentColor) { onChanged(config) }
                    Text("Focus ring, selection, and cursor use this color. \u{201C}Match System\u{201D} follows your macOS accent.")
                        .font(.system(size: 11))
                        .foregroundColor(DT.textHelp)
                } else {
                    Text("This theme sets its own accent color.")
                        .font(.system(size: 11))
                        .foregroundColor(DT.textHelp)
                }
            } header: {
                PrefsSectionHeader(title: "Theme")
            }

            Section {
                TextField("Font family", text: $config.appearance.fontFamily)
                    .onChange(of: config.appearance.fontFamily) { onChanged(config) }
                Text("Use a monospaced font for best results (e.g. SF Mono, Menlo, JetBrains Mono)")
                    .font(.system(size: 11))
                    .foregroundColor(DT.textHelp)
                Stepper("Size: \(config.appearance.fontSize)", value: $config.appearance.fontSize, in: 8...32)
                    .onChange(of: config.appearance.fontSize) { onChanged(config) }
            } header: {
                PrefsSectionHeader(title: "Font")
            }

            Section {
                Picker("Style", selection: $config.appearance.cursorStyle) {
                    Text("Block").tag(CursorStyle.block)
                    Text("Beam").tag(CursorStyle.beam)
                    Text("Underline").tag(CursorStyle.underline)
                }
                .onChange(of: config.appearance.cursorStyle) { onChanged(config) }
                Toggle("Blink cursor", isOn: $config.appearance.cursorBlink)
                    .onChange(of: config.appearance.cursorBlink) { onChanged(config) }
            } header: {
                PrefsSectionHeader(title: "Cursor")
            }

            Section {
                Slider(value: $config.appearance.windowOpacity, in: 0.3...1.0, step: 0.01) {
                    Text("Opacity: \(Int((config.appearance.windowOpacity * 100).rounded()))%")
                }
                .onChange(of: config.appearance.windowOpacity) { onChanged(config) }
                Text("Lower values create a translucent terminal window")
                    .font(.system(size: 11))
                    .foregroundColor(DT.textHelp)

                Slider(value: $config.appearance.chromeTranslucency, in: 0.0...0.6, step: 0.01) {
                    Text("Chrome translucency: \(Int((config.appearance.chromeTranslucency * 100).rounded()))%")
                }
                .onChange(of: config.appearance.chromeTranslucency) { onChanged(config) }
                Text("Frosts the sidebar, panels and header so the desktop shows through the theme color")
                    .font(.system(size: 11))
                    .foregroundColor(DT.textHelp)

                Toggle("Thin strokes (non-Retina)", isOn: $config.appearance.thinStrokes)
                    .onChange(of: config.appearance.thinStrokes) { onChanged(config) }
            } header: {
                PrefsSectionHeader(title: "Window")
            }
        }
        .themedGroupedForm()
    }
}

extension View {
    /// A grouped Form themed for the active appearance: hides the system list chrome (so the sheet
    /// takes the theme's base color) and tints every section card with the theme's elevated surface
    /// instead of the neutral system gray — so the Settings form colors with the rest of the app.
    func themedGroupedForm() -> some View {
        self
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .listRowBackground(DT.elevated)
    }
}

struct TerminalTab: View {
    @Binding var config: AppConfig
    let onChanged: (AppConfig) -> Void

    var body: some View {
        Form {
            Section {
                Stepper(
                    "Lines: \(config.terminal.scrollbackLines)", value: $config.terminal.scrollbackLines,
                    in: 1000...100000, step: 1000
                )
                .onChange(of: config.terminal.scrollbackLines) { onChanged(config) }
                Text("Number of lines to keep in the scrollback buffer")
                    .font(.system(size: 11))
                    .foregroundColor(DT.textHelp)
            } header: {
                PrefsSectionHeader(title: "Scrollback")
            }

            Section {
                Toggle("Copy on select", isOn: $config.terminal.copyOnSelect)
                    .onChange(of: config.terminal.copyOnSelect) { onChanged(config) }
                Text("Automatically copy selected text to the clipboard")
                    .font(.system(size: 11))
                    .foregroundColor(DT.textHelp)
                Toggle("Paste on right-click", isOn: $config.terminal.pasteOnRightClick)
                    .onChange(of: config.terminal.pasteOnRightClick) { onChanged(config) }
            } header: {
                PrefsSectionHeader(title: "Clipboard")
            }

            Section {
                Picker("Bell", selection: $config.terminal.bellBehavior) {
                    Text("Visual").tag(BellBehavior.visual)
                    Text("Audio").tag(BellBehavior.audio)
                    Text("None").tag(BellBehavior.none)
                }
                .onChange(of: config.terminal.bellBehavior) { onChanged(config) }
                Toggle("Mouse reporting", isOn: $config.terminal.mouseReporting)
                    .onChange(of: config.terminal.mouseReporting) { onChanged(config) }
                Text("Forward mouse events to terminal applications (e.g. vim, tmux)")
                    .font(.system(size: 11))
                    .foregroundColor(DT.textHelp)
                Toggle("Close pane on clean exit", isOn: $config.terminal.closeOnCleanExit)
                    .onChange(of: config.terminal.closeOnCleanExit) { onChanged(config) }
                Text("Automatically close the pane when the shell exits with code 0")
                    .font(.system(size: 11))
                    .foregroundColor(DT.textHelp)
            } header: {
                PrefsSectionHeader(title: "Behavior")
            }
        }
        .themedGroupedForm()
    }
}

struct SSHPrefsTab: View {
    @Binding var config: AppConfig
    let onChanged: (AppConfig) -> Void

    var body: some View {
        Form {
            Section {
                TextField(
                    "Default user",
                    text: Binding(
                        get: { config.ssh.defaultUser ?? "" },
                        set: { config.ssh.defaultUser = $0.isEmpty ? nil : $0 }
                    )
                )
                .onChange(of: config.ssh.defaultUser) { onChanged(config) }
                Text("Username to use when none is specified in the connection")
                    .font(.system(size: 11))
                    .foregroundColor(DT.textHelp)
            } header: {
                PrefsSectionHeader(title: "Defaults")
            }

            Section {
                Stepper(
                    "Keepalive: \(config.ssh.keepaliveInterval)s", value: $config.ssh.keepaliveInterval, in: 0...300,
                    step: 10
                )
                .onChange(of: config.ssh.keepaliveInterval) { onChanged(config) }
                Text("Interval in seconds between keepalive packets (0 to disable)")
                    .font(.system(size: 11))
                    .foregroundColor(DT.textHelp)
                Toggle("Auto-reconnect", isOn: $config.ssh.autoReconnect)
                    .onChange(of: config.ssh.autoReconnect) { onChanged(config) }
                Stepper(
                    "Max reconnect attempts: \(config.ssh.maxReconnectAttempts)",
                    value: $config.ssh.maxReconnectAttempts, in: 1...50
                )
                .onChange(of: config.ssh.maxReconnectAttempts) { onChanged(config) }
            } header: {
                PrefsSectionHeader(title: "Connection")
            }

            Section {
                Toggle("Agent forwarding", isOn: $config.ssh.agentForwarding)
                    .onChange(of: config.ssh.agentForwarding) { onChanged(config) }
                Text("Forward the local SSH agent to remote hosts")
                    .font(.system(size: 11))
                    .foregroundColor(DT.textHelp)
                Toggle("X11 forwarding", isOn: $config.ssh.x11Forwarding)
                    .onChange(of: config.ssh.x11Forwarding) { onChanged(config) }
                Toggle("ControlMaster multiplexing", isOn: $config.ssh.controlMaster)
                    .onChange(of: config.ssh.controlMaster) { onChanged(config) }
                Text("Share a single TCP connection across multiple SSH sessions to the same host")
                    .font(.system(size: 11))
                    .foregroundColor(DT.textHelp)
            } header: {
                PrefsSectionHeader(title: "Forwarding")
            }
        }
        .themedGroupedForm()
    }
}

struct KeysTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "keyboard")
                .font(.system(size: 28))
                .foregroundColor(DT.textFaint)
            Text("Keyboard shortcuts are configured in the menu bar.")
                .font(.system(size: 13))
                .foregroundColor(DT.textTertiary)
            Text("Custom key bindings will be available in a future update.")
                .font(.system(size: 11))
                .foregroundColor(DT.textHelp)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preferences Section Header

struct PrefsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.0)
            .foregroundColor(DT.textTertiary)
    }
}
