import SimpletonCore
// Sources/Simpleton/Views/WorkspacesPreferencesTab.swift
import SwiftUI

/// Settings → Workspaces. Manages saved workspaces: each one bundles the full preferences (theme,
/// font, cursor, SSH, general), AI config, a panel profile, enabled plugins, and a saved window
/// layout, and applying it swaps the whole environment. Modeled on ProfilesPreferencesTab — a list on
/// the left, an editor on the right — and themed the same way (accent selection, DT surfaces). The
/// list is driven by the shared WorkspaceStore so it stays in sync with the header switcher;
/// saves/deletes go through WorkspaceManager and broadcast `.simpletonWorkspacesChanged` so AppDelegate
/// re-reads the list. Two app-wide toggles (replace-window, keep-in-sync) plus the per-workspace
/// "set as default" write through the normal config onChange path.
struct WorkspacesPreferencesTab: View {
    let manager: WorkspaceManager
    @ObservedObject var registry: PanelRegistry
    let pluginManager: PluginManager
    @Binding var config: AppConfig
    let onChanged: (AppConfig) -> Void

    @ObservedObject private var store = WorkspaceStore.shared
    @ObservedObject private var themeSettings = ThemeSettings.shared
    @State private var selectedName: String?
    @State private var renaming: RenameTarget?
    @State private var renameText: String = ""

    /// Identifiable wrapper so `.sheet(item:)` can present the rename sheet keyed off a workspace name
    /// without conforming the stdlib `String` to `Identifiable` app-wide.
    private struct RenameTarget: Identifiable {
        let name: String
        var id: String { name }
    }

    var body: some View {
        HSplitView {
            // Left: workspace list + behavior toggles + "save current window" action.
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
                behaviorToggles
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
            .frame(width: 240)

            // Right: editor for the selected workspace.
            Group {
                if let name = selectedName, let ws = manager.load(name: name) {
                    WorkspaceEditor(
                        workspace: ws,
                        allThemes: ThemePalette.all,
                        allProfiles: registry.profiles,
                        allPlugins: pluginManager.scriptPlugins,
                        isActive: store.activeName == name,
                        isDefault: config.general.defaultWorkspace == name,
                        onApply: {
                            NotificationCenter.default.post(name: .simpletonOpenWorkspace, object: name)
                        },
                        onSaveSetup: { appearanceMode, accentColor, profileID, plugins in
                            saveSetup(
                                name: name, appearanceMode: appearanceMode, accentColor: accentColor,
                                profileID: profileID, plugins: plugins)
                        },
                        onRename: { beginRename(name) },
                        onDuplicate: { duplicate(name) },
                        onUpdateLayout: {
                            NotificationCenter.default.post(name: .simpletonUpdateWorkspaceLayout, object: name)
                        },
                        onSetDefault: { setDefault(name) },
                        onDelete: {
                            manager.delete(name: name)
                            if config.general.defaultWorkspace == name { setDefault(nil) }
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
        .sheet(item: $renaming) { target in
            renameSheet(for: target.name)
        }
    }

    /// App-wide workspace behavior. Both write straight through the config onChange path.
    private var behaviorToggles: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                "Opening a workspace replaces the current window",
                isOn: Binding(
                    get: { config.general.workspaceOpenReplacesWindow },
                    set: { config.general.workspaceOpenReplacesWindow = $0; onChanged(config) }
                )
            )
            .font(.system(size: 11))
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("workspace-replace-window")

            Toggle(
                "Keep the active workspace in sync with changes",
                isOn: Binding(
                    get: { config.general.autoSyncActiveWorkspace },
                    set: { config.general.autoSyncActiveWorkspace = $0; onChanged(config) }
                )
            )
            .font(.system(size: 11))
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("workspace-auto-sync")
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func workspaceRow(_ name: String) -> some View {
        Button(action: { selectedName = name }) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(name).font(.system(size: 12, weight: .medium))
                    if config.general.defaultWorkspace == name {
                        Text("default")
                            .font(.system(size: 8, weight: .semibold))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(themeSettings.accent.opacity(0.25))
                            .foregroundColor(themeSettings.accent)
                            .cornerRadius(3)
                            .accessibilityIdentifier("workspace-default-badge-\(name)")
                    }
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

    /// A one-line "theme • profile • font" summary for the list row, surfacing that a workspace now
    /// carries deeper prefs (font) beyond theme/profile.
    private func summary(for name: String) -> String {
        guard let ws = manager.load(name: name) else { return "Layout only" }
        // Prefer the theme from the full preferences (falls back to the legacy field).
        let themeID = ws.preferences?.appearance.appearanceMode ?? ws.appearanceMode
        let themeName =
            themeID.flatMap { id in ThemePalette.all.first(where: { $0.id == id })?.name } ?? themeID
        let profileName = ws.panelProfileID.flatMap { pid in
            registry.profiles.first(where: { $0.id.uuidString == pid })?.name
        }
        let fontName = ws.preferences?.appearance.fontFamily
        let parts = [themeName, profileName, fontName].compactMap { $0 }
        return parts.isEmpty ? "Layout only" : parts.joined(separator: " • ")
    }

    private func saveCurrentWindow() {
        NotificationCenter.default.post(name: .simpletonSaveWorkspaceRequested, object: nil)
    }

    // MARK: - Per-workspace actions

    private func setDefault(_ name: String?) {
        config.general.defaultWorkspace = name
        onChanged(config)
    }

    private func duplicate(_ name: String) {
        if let newName = manager.duplicate(name: name) {
            selectedName = newName
            NotificationCenter.default.post(name: .simpletonWorkspacesChanged, object: nil)
        }
    }

    private func beginRename(_ name: String) {
        renameText = name
        renaming = RenameTarget(name: name)
    }

    private func renameSheet(for name: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Workspace")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DT.textPrimary)
            TextField("Workspace name", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .accessibilityIdentifier("workspace-rename-field")
            HStack {
                Spacer()
                Button("Cancel") { renaming = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") {
                    let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if manager.rename(from: name, to: newName) {
                        // If this workspace was the default (or active), carry the marker to the new name.
                        if config.general.defaultWorkspace == name { setDefault(newName) }
                        if store.activeName == name { store.activeName = newName }
                        selectedName = newName
                        NotificationCenter.default.post(name: .simpletonWorkspacesChanged, object: nil)
                    }
                    renaming = nil
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
        .background(DT.base)
    }

    /// Reload the workspace (to preserve its captured `window` layout and deeper `preferences`/AI),
    /// overwrite only the setup fields the editor manages, persist, and broadcast the change.
    private func saveSetup(
        name: String, appearanceMode: String?, accentColor: String?, profileID: String?,
        plugins: [String]?
    ) {
        guard var ws = manager.load(name: name) else { return }
        ws.appearanceMode = appearanceMode
        ws.accentColor = accentColor
        ws.panelProfileID = profileID
        ws.enabledPlugins = plugins
        // Mirror the edited theme/accent into the stored full preferences too, so the deeper-prefs
        // apply path (which takes precedence over the legacy fields) reflects the editor's choice.
        if var prefs = ws.preferences {
            if let mode = appearanceMode { prefs.appearance.appearanceMode = mode }
            if let accent = accentColor { prefs.appearance.accentColor = accent }
            ws.preferences = prefs
        }
        try? manager.save(workspace: ws)
        NotificationCenter.default.post(name: .simpletonWorkspacesChanged, object: nil)
    }
}

/// Editor for one workspace's setup bundle. Theme/profile/plugin edits are staged locally and
/// committed with the Save Setup button; Apply / Rename / Duplicate / Update layout / Set default /
/// Delete act on the stored workspace immediately.
struct WorkspaceEditor: View {
    let workspace: Workspace
    let allThemes: [AppearanceTheme]
    let allProfiles: [PanelProfile]
    let allPlugins: [ScriptPlugin]
    let isActive: Bool
    let isDefault: Bool
    let onApply: () -> Void
    /// (appearanceMode, accentColor, panelProfileID, enabledPlugins)
    let onSaveSetup: (String?, String?, String?, [String]?) -> Void
    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onUpdateLayout: () -> Void
    let onSetDefault: () -> Void
    let onDelete: () -> Void

    // Sentinel tags for "don't change this facet on apply" (a nil field on the Workspace).
    private static let keepTheme = "__keep__"
    private static let keepProfile = "__keep__"

    @State private var themeID: String
    @State private var profileID: String
    @State private var enabledPlugins: Set<String>

    init(
        workspace: Workspace, allThemes: [AppearanceTheme], allProfiles: [PanelProfile],
        allPlugins: [ScriptPlugin], isActive: Bool, isDefault: Bool,
        onApply: @escaping () -> Void, onSaveSetup: @escaping (String?, String?, String?, [String]?) -> Void,
        onRename: @escaping () -> Void, onDuplicate: @escaping () -> Void,
        onUpdateLayout: @escaping () -> Void, onSetDefault: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.workspace = workspace
        self.allThemes = allThemes
        self.allProfiles = allProfiles
        self.allPlugins = allPlugins
        self.isActive = isActive
        self.isDefault = isDefault
        self.onApply = onApply
        self.onSaveSetup = onSaveSetup
        self.onRename = onRename
        self.onDuplicate = onDuplicate
        self.onUpdateLayout = onUpdateLayout
        self.onSetDefault = onSetDefault
        self.onDelete = onDelete
        _themeID = State(
            initialValue: workspace.preferences?.appearance.appearanceMode ?? workspace.appearanceMode
                ?? Self.keepTheme)
        _profileID = State(initialValue: workspace.panelProfileID ?? Self.keepProfile)
        _enabledPlugins = State(initialValue: Set(workspace.enabledPlugins ?? []))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Text(workspace.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DT.textPrimary)
                    if isDefault {
                        Text("default")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(DT.accent.opacity(0.2))
                            .foregroundColor(DT.accent)
                            .cornerRadius(4)
                    }
                }

                // Deeper-prefs summary: surface font/cursor carried by this workspace so it's visible
                // that a workspace now stores more than theme/profile.
                if let prefs = workspace.preferences {
                    prefsSummary(prefs)
                }

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

                // Primary actions.
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

                // Manage actions (rename / duplicate / update layout / set default).
                fieldGroup("Manage") {
                    HStack(spacing: 8) {
                        Button("Rename") { onRename() }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("workspace-rename")
                        Button("Duplicate") { onDuplicate() }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("workspace-duplicate")
                        Button("Update layout from current window") { onUpdateLayout() }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("workspace-update-layout")
                    }
                    Button(isDefault ? "Default on launch ✓" : "Set as default") { onSetDefault() }
                        .buttonStyle(.bordered)
                        .disabled(isDefault)
                        .accessibilityIdentifier("workspace-set-default")
                }

                Text(
                    "Applying a workspace swaps its full preferences (theme, font, cursor, SSH), AI "
                        + "config, panel profile, enabled plugins, and restores its saved window layout. "
                        + "\u{201C}Don't change\u{201D} leaves that facet as-is. \u{201C}Update layout\u{201D} "
                        + "re-captures the current window's panes without touching the saved settings.")
                    .font(.system(size: 11))
                    .foregroundColor(DT.textHelp)
            }
            .padding(16)
        }
    }

    /// One-line font/cursor readout from the captured preferences.
    private func prefsSummary(_ prefs: AppConfig) -> some View {
        HStack(spacing: 10) {
            Label("\(prefs.appearance.fontFamily) \(prefs.appearance.fontSize)pt", systemImage: "textformat")
            Label(cursorLabel(prefs.appearance.cursorStyle), systemImage: "cursorarrow")
        }
        .font(.system(size: 11))
        .foregroundColor(DT.textTertiary)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DT.surface)
        .cornerRadius(6)
    }

    private func cursorLabel(_ style: CursorStyle) -> String {
        switch style {
        case .block: return "Block cursor"
        case .beam: return "Beam cursor"
        case .underline: return "Underline cursor"
        }
    }

    private func fieldGroup<Content: View>(_ label: String, @ViewBuilder content: () -> Content)
        -> some View
    {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
            content()
        }
    }
}
