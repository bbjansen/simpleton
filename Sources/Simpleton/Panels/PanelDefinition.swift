// Sources/Simpleton/Panels/PanelDefinition.swift
import AppKit
import SimpletonCore

enum PanelSide: String, Codable {
    case left, right
}

protocol PanelDefinition: AnyObject {
    var id: String { get }
    var name: String { get }
    var icon: String { get }          // SF Symbol name
    var description: String { get }
    var defaultSide: PanelSide { get }
    var isBuiltIn: Bool { get }
    func makeViewController(context: PanelContext) -> NSViewController
}

struct PanelContext {
    var tabContainer: () -> TabContainerController?
    var skillStore: SkillStore?
    var bookmarkStore: BookmarkStore?
    var aiService: AIService?
    var sshConfigWatcher: SSHConfigWatcher?
    var appConfig: AppConfig
    var currentPane: () -> PaneController?
    var onInsertCommand: (String) -> Void
    var appSupportDir: URL
}
