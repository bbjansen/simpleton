import SimpletonCore
// Sources/Simpleton/Views/WorkspacesPreferencesTab.swift
import SwiftUI

/// Settings → Workspaces. Manages saved workspaces: each one bundles a theme + accent + panel
/// profile + enabled plugins + a saved window layout, and applying it swaps the whole environment.
/// Modeled on ProfilesPreferencesTab — a list on the left, an editor on the right — and themed the
/// same way (accent selection, DT surfaces). The list is driven by the shared WorkspaceStore so it
/// stays in sync with the header switcher; saves/deletes go through WorkspaceManager and broadcast
/// `.simpletonWorkspacesChanged` so AppDelegate re-reads the list.
struct WorkspacesPreferencesTab: View {
    let manager: WorkspaceManager
    @ObservedObject var registry: PanelRegistry
    let pluginManager: PluginManager

    @ObservedObject private var store = WorkspaceStore.shared
    @ObservedObject private var themeSettings = ThemeSettings.shared
    @State private var selectedName: String?

    var body: some View {
        HSplitView {
            // Left: workspace list + "save current window" action.
            VStack(spacing: 0) {
                if store.names.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "rectangle.3.group")
                            .font(.system(size: 22))
                            .foregroundColor(.secondary)
                        Text("No workspaces yet")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 8)
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(store.names, id: \.self) { name in
                                workspaceRow(name)
                            }
                        }
                        .padding(6)
                    }
                }
                Divider()
                HStack {
                    Button(action: saveCurrentWindow) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("Save current window as a new workspace")
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("workspace-save-current")
                    Spacer()
                }
                .padding(8)
            }
            .frame(width: 220)

            // Right: editor for the selected workspace.
            Group {
                if let name = selectedName, let ws = manager.load(name: name) {
                    WorkspaceEditor(
                        workspace: ws,
                        allThemes: ThemePalette.all,
                        allProfiles: registry.profiles,
                        allPlugins: pluginManager.scriptPlugins,
                        isActive: store.activeName == name,
                        onApply: {
                            NotificationCenter.default.post(name: .simpletonOpenWorkspace, object: name)
                        },
                        onSaveSetup: { appearanceMode, accentColor, profileID, plugins in
                            saveSetup(
                                name: name, appearanceMode: appearanceMode, accentColor: accentColor,
                                profileID: profileID, plugins: plugins)
                        },
                        onDelete: {
                            manager.delete(name: name)
                            selectedName = nil
                            NotificationCenter.default.post(name: .simpletonWorkspacesChanged, object: nil)
                        }
                    )
                    .id(name)
                } else {
                    Text("Select a workspace")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func workspaceRow(_ name: String) -> some View {
        Button(action: { selectedName = name }) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(name).font(.system(size: 12, weight: .medium))
                    Spacer()
                    if store.activeName == name {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10))
                            .foregroundColor(themeSettings.accent)
                    }
                }
                Text(summary(for: name))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(selectedName == name ? themeSettings.accent.opacity(0.25) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("workspace-row-\(name)")
    }

    /// A one-line "theme • profile" summary for the list row.
    private func summary(for name: String) -> String {
        guard let ws = manager.load(name: name) else { return "Layout only" }
        let themeName =
            ws.appearanceMode.flatMap { id in ThemePalette.all.first(where: { $0.id == id })?.name }
            ?? ws.appearanceMode
        let profileName = ws.panelProfileID.flatMap { pid in
            registry.profiles.first(where: { $0.id.uuidString == pid })?.name
        }
        let parts = [themeName, profileName].compactMap { $0 }
        return parts.isEmpty ? "Layout only" : parts.joined(separator: " • ")
    }

    private func saveCurrentWindow() {
        NotificationCenter.default.post(name: .simpletonSaveWorkspaceRequested, object: nil)
    }

    /// Reload the workspace (to preserve its captured `window` layout), overwrite only the setup
    /// fields the editor manages, persist, and broadcast the change.
    private func saveSetup(
        name: String, appearanceMode: String?, accentColor: String?, profileID: String?,
        plugins: [String]?
    ) {
        guard var ws = manager.load(name: name) else { return }
        ws.appearanceMode = appearanceMode
        ws.accentColor = accentColor
        ws.panelProfileID = profileID
        ws.enabledPlugins = plugins
        try? manager.save(workspace: ws)
        NotificationCenter.default.post(name: .simpletonWorkspacesChanged, object: nil)
    }
}

/// Editor for one workspace's setup bundle. Edits are staged locally and committed with the Save
/// Setup button (Apply / Delete act on the stored workspace immediately).
struct WorkspaceEditor: View {
    let workspace: Workspace
    let allThemes: [AppearanceTheme]
    let allProfiles: [PanelProfile]
    let allPlugins: [ScriptPlugin]
    let isActive: Bool
    let onApply: () -> Void
    /// (appearanceMode, accentColor, panelProfileID, enabledPlugins)
    let onSaveSetup: (String?, String?, String?, [String]?) -> Void
    let onDelete: () -> Void

    // Sentinel tags for "don't change this facet on apply" (a nil field on the Workspace).
    private static let keepTheme = "__keep__"
    private static let keepProfile = "__keep__"

    @State private var themeID: String
    @State private var profileID: String
    @State private var enabledPlugins: Set<String>

    init(
        workspace: Workspace, allThemes: [AppearanceTheme], allProfiles: [PanelProfile],
        allPlugins: [ScriptPlugin], isActive: Bool,
        onApply: @escaping () -> Void, onSaveSetup: @escaping (String?, String?, String?, [String]?) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.workspace = workspace
        self.allThemes = allThemes
        self.allProfiles = allProfiles
        self.allPlugins = allPlugins
        self.isActive = isActive
        self.onApply = onApply
        self.onSaveSetup = onSaveSetup
        self.onDelete = onDelete
        _themeID = State(initialValue: workspace.appearanceMode ?? Self.keepTheme)
        _profileID = State(initialValue: workspace.panelProfileID ?? Self.keepProfile)
        _enabledPlugins = State(initialValue: Set(workspace.enabledPlugins ?? []))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(workspace.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DT.textPrimary)

                fieldGroup("Theme") {
                    Picker("", selection: $themeID) {
                        Text("Don't change").tag(Self.keepTheme)
                        Divider()
                        ForEach(allThemes) { theme in
                            Text(theme.name).tag(theme.id)
                        }
                    }
                    .labelsHidden()
                }

                fieldGroup("Panel profile") {
                    Picker("", selection: $profileID) {
                        Text("Don't change").tag(Self.keepProfile)
                        Divider()
                        ForEach(allProfiles) { profile in
                            Text(profile.name).tag(profile.id.uuidString)
                        }
                    }
                    .labelsHidden()
                }

                fieldGroup("Plugins") {
                    if allPlugins.isEmpty {
                        Text("No plugins installed")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(allPlugins, id: \.name) { plugin in
                                Toggle(
                                    plugin.name,
                                    isOn: Binding(
                                        get: { enabledPlugins.contains(plugin.name) },
                                        set: { on in
                                            if on { enabledPlugins.insert(plugin.name) }
                                            else { enabledPlugins.remove(plugin.name) }
                                        }
                                    )
                                )
                                .font(.system(size: 12))
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button(isActive ? "Applied" : "Apply") { onApply() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("workspace-apply")
                    Button("Save Setup") {
                        onSaveSetup(
                            themeID == Self.keepTheme ? nil : themeID,
                            workspace.accentColor,
                            profileID == Self.keepProfile ? nil : profileID,
                            enabledPlugins.isEmpty ? nil : Array(enabledPlugins).sorted()
                        )
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("workspace-save-setup")
                    Spacer()
                    Button("Delete") { onDelete() }
                        .foregroundColor(.red)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("workspace-delete")
                }

                Text(
                    "Applying a workspace swaps the theme, panel profile, enabled plugins, and restores "
                        + "its saved window layout in a new window. \u{201C}Don't change\u{201D} leaves that "
                        + "facet as-is.")
                    .font(.system(size: 11))
                    .foregroundColor(DT.textHelp)
            }
            .padding(16)
        }
    }

    private func fieldGroup<Content: View>(_ label: String, @ViewBuilder content: () -> Content)
        -> some View
    {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
            content()
        }
    }
}
