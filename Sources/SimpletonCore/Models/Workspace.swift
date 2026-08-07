// Sources/SimpletonCore/Models/Workspace.swift
import Foundation

/// A named, switchable setup. Beyond the saved window layout it can carry a theme, accent, panel
/// profile, and the set of enabled plugins — applied together when the workspace is opened, so one
/// pick swaps the whole environment. The setup fields are optional: a nil field means "leave that
/// facet unchanged" on apply, and keeps older workspace files (layout-only) loading unchanged.
public struct Workspace: Codable, Equatable {
    public var name: String
    public var savedAt: Date
    public var window: WindowState

    /// Theme id (e.g. "dark", "tangerine", "nebula"). Nil = don't change the theme on apply.
    public var appearanceMode: String?
    /// Accent id for neutral themes. Nil = don't change.
    public var accentColor: String?
    /// The panel profile to activate (UUID string). Nil = don't change the profile.
    public var panelProfileID: String?
    /// The plugin ids enabled in this workspace. Nil = don't change plugin enablement.
    public var enabledPlugins: [String]?

    /// The full app preferences captured with this workspace (theme, font, cursor, SSH, general).
    /// Applied wholesale on open — carrying much more than the legacy appearanceMode/accent fields,
    /// which remain as a fallback for older workspace files that predate this. Nil = fall back to the
    /// legacy appearance fields. NOTE: the global workspace-management fields
    /// (general.defaultWorkspace / workspaceOpenReplacesWindow / autoSyncActiveWorkspace) are blanked
    /// out here at capture time so opening a workspace never rewrites those app-wide settings.
    public var preferences: AppConfig?
    /// The AI provider/model configuration captured with this workspace. Nil = don't change AI config.
    public var aiConfig: AIConfig?

    public init(
        name: String, savedAt: Date = Date(), window: WindowState,
        appearanceMode: String? = nil, accentColor: String? = nil,
        panelProfileID: String? = nil, enabledPlugins: [String]? = nil,
        preferences: AppConfig? = nil, aiConfig: AIConfig? = nil
    ) {
        self.name = name
        self.savedAt = savedAt
        self.window = window
        self.appearanceMode = appearanceMode
        self.accentColor = accentColor
        self.panelProfileID = panelProfileID
        self.enabledPlugins = enabledPlugins
        self.preferences = preferences
        self.aiConfig = aiConfig
    }
}

public struct WorkspaceFile: Codable {
    public let version: Int
    public var workspace: Workspace

    private enum CodingKeys: String, CodingKey {
        case version, name, savedAt, window
        case appearanceMode, accentColor, panelProfileID, enabledPlugins
        case preferences, aiConfig
    }

    public init(version: Int = 1, workspace: Workspace) {
        self.version = version
        self.workspace = workspace
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        let name = try container.decode(String.self, forKey: .name)
        let savedAt = try container.decode(Date.self, forKey: .savedAt)
        let window = try container.decode(WindowState.self, forKey: .window)
        // Setup bundle — optional, so layout-only files written before this feature still load.
        let appearanceMode = try container.decodeIfPresent(String.self, forKey: .appearanceMode)
        let accentColor = try container.decodeIfPresent(String.self, forKey: .accentColor)
        let panelProfileID = try container.decodeIfPresent(String.self, forKey: .panelProfileID)
        let enabledPlugins = try container.decodeIfPresent([String].self, forKey: .enabledPlugins)
        // Deeper setup — optional, so files written before this feature (no preferences/aiConfig) still load.
        let preferences = try container.decodeIfPresent(AppConfig.self, forKey: .preferences)
        let aiConfig = try container.decodeIfPresent(AIConfig.self, forKey: .aiConfig)
        workspace = Workspace(
            name: name, savedAt: savedAt, window: window,
            appearanceMode: appearanceMode, accentColor: accentColor,
            panelProfileID: panelProfileID, enabledPlugins: enabledPlugins,
            preferences: preferences, aiConfig: aiConfig)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(workspace.name, forKey: .name)
        try container.encode(workspace.savedAt, forKey: .savedAt)
        try container.encode(workspace.window, forKey: .window)
        try container.encodeIfPresent(workspace.appearanceMode, forKey: .appearanceMode)
        try container.encodeIfPresent(workspace.accentColor, forKey: .accentColor)
        try container.encodeIfPresent(workspace.panelProfileID, forKey: .panelProfileID)
        try container.encodeIfPresent(workspace.enabledPlugins, forKey: .enabledPlugins)
        try container.encodeIfPresent(workspace.preferences, forKey: .preferences)
        try container.encodeIfPresent(workspace.aiConfig, forKey: .aiConfig)
    }
}
