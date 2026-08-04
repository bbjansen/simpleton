// Sources/Simpleton/Plugins/ScriptPlugin.swift
import Foundation

struct ScriptPluginCommand: Codable {
    let id: String
    let title: String
    let shortcut: String?
}

struct ScriptPluginPanelManifest: Codable {
    let id: String
    let name: String
    let icon: String
    let defaultSide: PanelSide
    let entrypoint: String  // relative path to the HTML file within the plugin directory
}

struct ScriptPluginManifest: Codable {
    let name: String
    let version: String
    let description: String?
    let author: String?
    let entrypoint: String
    let events: [String]?
    let commands: [ScriptPluginCommand]?
    let permissions: [String]?
    let panels: [ScriptPluginPanelManifest]?
}

/// A loaded script plugin — manifest + directory path.
final class ScriptPlugin {
    let manifest: ScriptPluginManifest
    let directory: URL
    var isEnabled: Bool

    var name: String { manifest.name }
    var version: String { manifest.version }
    var entrypointURL: URL { directory.appendingPathComponent(manifest.entrypoint) }
    var subscribedEvents: Set<String> { Set(manifest.events ?? []) }
    var registeredCommands: [ScriptPluginCommand] { manifest.commands ?? [] }
    var grantedPermissions: Set<String> { Set(manifest.permissions ?? []) }

    init(manifest: ScriptPluginManifest, directory: URL, isEnabled: Bool = true) {
        self.manifest = manifest
        self.directory = directory
        self.isEnabled = isEnabled
    }

    /// Load a script plugin from a directory containing plugin.json.
    static func load(from directory: URL) -> ScriptPlugin? {
        let manifestURL = directory.appendingPathComponent("plugin.json")
        guard let data = try? Data(contentsOf: manifestURL),
            let manifest = try? JSONDecoder().decode(ScriptPluginManifest.self, from: data)
        else {
            return nil
        }
        // Verify entrypoint exists and is executable
        let entrypoint = directory.appendingPathComponent(manifest.entrypoint)
        guard FileManager.default.isExecutableFile(atPath: entrypoint.path) else {
            return nil
        }
        return ScriptPlugin(manifest: manifest, directory: directory)
    }
}
