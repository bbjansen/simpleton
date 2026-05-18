// Sources/Simpleton/Panels/BuiltInPanels.swift
import AppKit
import SwiftUI
import SimpletonCore

extension PanelDefinition {

    static let connections = PanelDefinition(
        id: PanelProfile.PanelID.connections,
        name: "Connections",
        icon: "network",
        description: "SSH connections and bookmarks",
        defaultSide: .left,
        isBuiltIn: true
    ) { context in
        guard let bookmarkStore = context.bookmarkStore else { return NSViewController() }
        let host = SidebarHostController(
            bookmarkStore: bookmarkStore,
            sshConfigWatcher: context.sshConfigWatcher,
            config: context.appConfig
        )
        host.onConnect = { bookmark in context.tabContainer()?.openSSHConnection(bookmark: bookmark) }
        host.onNewConnection = {
            guard let window = context.tabContainer()?.view.window else { return }
            NotificationCenter.default.post(name: .simpletonShowNewConnection, object: window)
        }
        return host
    }

    static let aiChat = PanelDefinition(
        id: PanelProfile.PanelID.aiChat,
        name: "AI Chat",
        icon: "sparkles",
        description: "AI-powered terminal assistant",
        defaultSide: .right,
        isBuiltIn: true
    ) { context in
        guard let aiService = context.aiService else { return NSViewController() }
        let vc = AIChatPanelController(aiService: aiService)
        vc.skillStore = context.skillStore
        vc.currentPaneProvider = context.currentPane
        vc.contextProvider = {
            guard let pane = context.currentPane() else {
                return AIContext(os: "macOS", recentCommands: [])
            }
            let shell: String?
            if case .local(let sh, _) = pane.connectionType { shell = sh } else { shell = nil }
            return AIContextBuilder.build(
                terminalView: pane.terminalView,
                cwd: pane.currentDirectory,
                shell: shell,
                includeSelection: true
            )
        }
        vc.onInsertCommand = context.onInsertCommand
        vc.onDismiss = nil
        return vc
    }

    static let skills = PanelDefinition(
        id: PanelProfile.PanelID.skills,
        name: "Skills",
        icon: "bolt",
        description: "Run and manage AI skills",
        defaultSide: .right,
        isBuiltIn: true
    ) { context in
        NSHostingController(rootView: SkillsPanelView(
            skillStore: context.skillStore,
            aiService: context.aiService,
            currentPaneProvider: context.currentPane
        ))
    }

    static let notes = PanelDefinition(
        id: PanelProfile.PanelID.notes,
        name: "Notes",
        icon: "note.text",
        description: "Per-directory scratchpad",
        defaultSide: .left,
        isBuiltIn: true
    ) { context in
        NSHostingController(rootView: NotesPanelView(
            appSupportDir: context.appSupportDir,
            currentPaneProvider: context.currentPane
        ))
    }

    static let snippets = PanelDefinition(
        id: PanelProfile.PanelID.snippets,
        name: "Snippets",
        icon: "text.insert",
        description: "Command templates with placeholders",
        defaultSide: .left,
        isBuiltIn: true
    ) { context in
        NSHostingController(rootView: SnippetsPanelView(
            appSupportDir: context.appSupportDir,
            onInsert: context.onInsertCommand
        ))
    }

    static let history = PanelDefinition(
        id: PanelProfile.PanelID.history,
        name: "History",
        icon: "clock",
        description: "Searchable shell command history",
        defaultSide: .left,
        isBuiltIn: true
    ) { context in
        NSHostingController(rootView: HistoryPanelView(
            shell: context.appConfig.general.shell,
            onInsert: context.onInsertCommand
        ))
    }

    static let environment = PanelDefinition(
        id: PanelProfile.PanelID.environment,
        name: "Environment",
        icon: "list.bullet.rectangle",
        description: "Shell environment variables",
        defaultSide: .left,
        isBuiltIn: true
    ) { context in
        NSHostingController(rootView: EnvironmentPanelView(
            shell: context.appConfig.general.shell,
            currentPaneProvider: context.currentPane
        ))
    }

    static let fileBrowser = PanelDefinition(
        id: PanelProfile.PanelID.fileBrowser,
        name: "File Browser",
        icon: "folder",
        description: "Browse the local filesystem",
        defaultSide: .left,
        isBuiltIn: true
    ) { context in
        NSHostingController(rootView: FileBrowserPanelView(
            onInsert: context.onInsertCommand,
            currentPaneProvider: context.currentPane
        ))
    }
}
