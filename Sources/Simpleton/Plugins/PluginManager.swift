// Sources/Simpleton/Plugins/PluginManager.swift
import Foundation
import SimpletonCore

/// Plugin event types matching the spec.
enum PluginEvent: String {
    case onSSHAuthenticated = "on-ssh-authenticated"
    case onSSHDisconnected = "on-ssh-disconnected"
    case onTabOpen = "on-tab-open"
    case onTabClose = "on-tab-close"
    case onStartup = "on-startup"
    case onShutdown = "on-shutdown"
    case onPaneExit = "on-pane-exit"
}

/// Central plugin coordinator — discovers, loads, and manages all plugins.
final class PluginManager {

    private let baseDirectory: URL // ~/Library/Application Support/Simpleton/
    private let runner = ScriptPluginRunner()
    private let actionHandler = ScriptActionHandler()

    private(set) var themeDiscovery: ThemeDiscovery
    private(set) var scriptPlugins: [ScriptPlugin] = []

    /// Combined commands from all script plugins (for Command Palette).
    var pluginCommands: [(pluginName: String, command: ScriptPluginCommand)] {
        scriptPlugins
            .filter(\.isEnabled)
            .flatMap { plugin in
                plugin.registeredCommands.map { (plugin.name, $0) }
            }
    }

    /// Paste handler — set by AppDelegate to paste into focused terminal.
    var pasteHandler: ((String) -> Void)?

    /// Command handler — set by AppDelegate to run a command by ID.
    var commandHandler: ((String) -> Void)?

    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
        let themesDir = baseDirectory.appendingPathComponent("themes")
        self.themeDiscovery = ThemeDiscovery(directory: themesDir)
    }

    /// Discover and load all plugins. Call once at startup.
    func loadAll() {
        // Tier 1: themes
        themeDiscovery.start()

        // Tier 2: scripts
        loadScriptPlugins()
    }

    /// Unload all plugins. Call at shutdown.
    func unloadAll() {
        themeDiscovery.stop()
        scriptPlugins.removeAll()
    }

    /// Reload script plugins (e.g., after user installs a new one).
    func reloadScripts() {
        loadScriptPlugins()
    }

    /// Fire an event to all subscribed script plugins.
    func fireEvent(_ event: PluginEvent, context: [String: Any] = [:]) {
        for plugin in scriptPlugins where plugin.isEnabled {
            runner.run(plugin: plugin, event: event.rawValue, context: context) { [weak self] result in
                guard let self = self else { return }
                for action in result.actions {
                    _ = self.actionHandler.handle(
                        action: action,
                        plugin: plugin,
                        pasteHandler: self.pasteHandler,
                        commandHandler: self.commandHandler
                    )
                }
            }
        }
    }

    /// Enable or disable a script plugin and persist the choice so it survives
    /// reloads and app restarts. The enabled state is keyed by plugin name in
    /// UserDefaults (plugins carry no persistent identity in their manifest).
    func setEnabled(_ enabled: Bool, for plugin: ScriptPlugin) {
        plugin.isEnabled = enabled
        var states = Self.persistedEnabledStates()
        states[plugin.name] = enabled
        UserDefaults.standard.set(states, forKey: Self.enabledStatesKey)
    }

    private static let enabledStatesKey = "simpletonPluginEnabledStates"

    private static func persistedEnabledStates() -> [String: Bool] {
        (UserDefaults.standard.dictionary(forKey: enabledStatesKey) as? [String: Bool]) ?? [:]
    }

    /// Execute a plugin command by ID.
    func executeCommand(id: String) {
        for plugin in scriptPlugins where plugin.isEnabled {
            if plugin.registeredCommands.contains(where: { $0.id == id }) {
                let context: [String: Any] = ["commandId": id]
                runner.run(plugin: plugin, event: "command", context: context) { [weak self] result in
                    guard let self = self else { return }
                    for action in result.actions {
                        _ = self.actionHandler.handle(
                            action: action,
                            plugin: plugin,
                            pasteHandler: self.pasteHandler,
                            commandHandler: self.commandHandler
                        )
                    }
                }
            }
        }
    }

    // MARK: - Private

    private func loadScriptPlugins() {
        let scriptsDir = baseDirectory.appendingPathComponent("scripts")
        try? FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true)

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: scriptsDir,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            scriptPlugins = []
            return
        }

        let states = Self.persistedEnabledStates()
        scriptPlugins = contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .compactMap { ScriptPlugin.load(from: $0) }
            .map { plugin in
                if let enabled = states[plugin.name] { plugin.isEnabled = enabled }
                return plugin
            }
    }
}
