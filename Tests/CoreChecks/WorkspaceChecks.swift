// Tests/CoreChecks/WorkspaceChecks.swift
//
// Round-trip + backward-compatibility coverage for the Workspace model, including the deeper
// per-workspace preferences (full AppConfig) and AI config added on top of the legacy
// appearanceMode/accent fields.
import Foundation
import SimpletonCore

func runWorkspaceChecks(_ t: TestRunner) {
    // A minimal single-pane window layout to attach to test workspaces.
    func sampleWindow() -> WindowState {
        WindowState(
            frame: WindowFrame(x: 100, y: 120, width: 1000, height: 700),
            tabs: [TabState(title: "zsh", splitTree: .pane(paneConn: .local(workingDirectory: "/tmp")))])
    }

    t.suite("Workspace.deeperPrefsRoundTrip") {
        do {
            var prefs = AppConfig()
            prefs.appearance.appearanceMode = "nebula"
            prefs.appearance.fontFamily = "Courier New"
            prefs.appearance.fontSize = 17
            prefs.appearance.cursorStyle = .beam
            prefs.ssh.defaultUser = "root"
            prefs.terminal.scrollbackLines = 42000
            var ai = AIConfig()
            ai.enabled = true
            ai.provider = .openai
            ai.model = "gpt-4o"

            let ws = Workspace(
                name: "Deep WS", window: sampleWindow(),
                appearanceMode: "nebula", accentColor: "blue",
                panelProfileID: "ABC-123", enabledPlugins: ["git", "docker"],
                preferences: prefs, aiConfig: ai)

            let data = try JSONEncoder().encode(WorkspaceFile(workspace: ws))
            let decoded = try JSONDecoder().decode(WorkspaceFile.self, from: data).workspace

            t.expectEqual(decoded.name, "Deep WS", "name")
            t.expectEqual(decoded.appearanceMode, "nebula", "legacy appearanceMode")
            t.expectEqual(decoded.accentColor, "blue", "legacy accentColor")
            t.expectEqual(decoded.panelProfileID, "ABC-123", "panelProfileID")
            t.expectEqual(decoded.enabledPlugins ?? [], ["git", "docker"], "enabledPlugins")
            // Deeper preferences survive the round-trip.
            t.expect(decoded.preferences != nil, "preferences present")
            t.expectEqual(decoded.preferences?.appearance.fontFamily, "Courier New", "prefs.fontFamily")
            t.expectEqual(decoded.preferences?.appearance.fontSize, 17, "prefs.fontSize")
            t.expectEqual(decoded.preferences?.appearance.cursorStyle, .beam, "prefs.cursorStyle")
            t.expectEqual(decoded.preferences?.ssh.defaultUser, "root", "prefs.ssh.defaultUser")
            t.expectEqual(decoded.preferences?.terminal.scrollbackLines, 42000, "prefs.scrollbackLines")
            // AI config survives the round-trip.
            t.expectEqual(decoded.aiConfig?.enabled, true, "ai.enabled")
            t.expectEqual(decoded.aiConfig?.provider, .openai, "ai.provider")
            t.expectEqual(decoded.aiConfig?.model, "gpt-4o", "ai.model")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    t.suite("Workspace.newWorkspaceManagementFields") {
        // The three global workspace-management fields default off / nil and round-trip on the config.
        let d = AppConfig()
        t.expectEqual(d.general.defaultWorkspace, nil, "defaultWorkspace default")
        t.expectEqual(d.general.workspaceOpenReplacesWindow, false, "workspaceOpenReplacesWindow default")
        t.expectEqual(d.general.autoSyncActiveWorkspace, false, "autoSyncActiveWorkspace default")
        do {
            var config = AppConfig()
            config.general.defaultWorkspace = "Prod"
            config.general.workspaceOpenReplacesWindow = true
            config.general.autoSyncActiveWorkspace = true
            let data = try JSONEncoder().encode(ConfigFile(config: config))
            let decoded = try JSONDecoder().decode(ConfigFile.self, from: data).config
            t.expectEqual(decoded.general.defaultWorkspace, "Prod", "defaultWorkspace round-trip")
            t.expectEqual(decoded.general.workspaceOpenReplacesWindow, true, "replace round-trip")
            t.expectEqual(decoded.general.autoSyncActiveWorkspace, true, "autoSync round-trip")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    t.suite("Workspace.legacyFileStillLoads") {
        do {
            // A layout-only workspace as written BEFORE this feature: no setup bundle, no
            // preferences / aiConfig. `encodeIfPresent` omits those keys entirely, so the serialized
            // form matches a genuine pre-feature file — and it must decode with the new fields nil.
            let legacy = Workspace(name: "Old WS", window: sampleWindow())
            t.expect(legacy.preferences == nil, "constructed legacy has nil preferences")
            let data = try JSONEncoder().encode(WorkspaceFile(workspace: legacy))
            let jsonString = String(data: data, encoding: .utf8) ?? ""
            // Prove the omitted-key contract: the on-disk JSON carries none of the new/optional keys.
            t.expect(!jsonString.contains("preferences"), "no preferences key on disk")
            t.expect(!jsonString.contains("aiConfig"), "no aiConfig key on disk")
            t.expect(!jsonString.contains("appearanceMode"), "no appearanceMode key on disk")

            let decoded = try JSONDecoder().decode(WorkspaceFile.self, from: data).workspace
            t.expectEqual(decoded.name, "Old WS", "legacy name")
            t.expect(decoded.preferences == nil, "legacy preferences nil")
            t.expect(decoded.aiConfig == nil, "legacy aiConfig nil")
            t.expect(decoded.appearanceMode == nil, "legacy appearanceMode nil")
            t.expectEqual(decoded.window.tabs.count, 1, "legacy layout preserved")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }
}
