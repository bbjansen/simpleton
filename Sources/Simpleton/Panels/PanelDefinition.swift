// Sources/Simpleton/Panels/PanelDefinition.swift
import AppKit
import SimpletonCore

enum PanelSide: String, Codable {
    case left, right
}

/// A panel registered in the activity bar.
///
/// Rather than a protocol + per-panel class, panels are plain value types:
/// static metadata (id, name, icon…) plus a factory closure that builds the
/// NSViewController on demand.  Adding a new panel means adding one static
/// property — no new file, no new class.
struct PanelDefinition {
    let id: String
    let name: String
    let icon: String          // SF Symbol name
    let description: String
    let defaultSide: PanelSide
    let isBuiltIn: Bool
    let make: (PanelContext) -> NSViewController
}

struct PanelContext {
    var tabContainer: () -> TabContainerController?
    var skillStore: SkillStore?
    var memoryStore: MemoryStore?
    var projectIndexer: ProjectIndexer?
    var bookmarkStore: BookmarkStore?
    var aiService: AIService?
    var sshConfigWatcher: SSHConfigWatcher?
    var appConfig: AppConfig
    var currentPane: () -> PaneController?
    var onInsertCommand: (String) -> Void
    var appSupportDir: URL
}
