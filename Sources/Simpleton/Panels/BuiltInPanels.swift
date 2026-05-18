// Sources/Simpleton/Panels/BuiltInPanels.swift
import AppKit
import SwiftUI
import SimpletonCore

// MARK: - Connections

final class ConnectionsPanelDefinition: PanelDefinition {
    let id = "connections"
    let name = "Connections"
    let icon = "network"
    let description = "SSH connections and bookmarks"
    let defaultSide = PanelSide.left
    let isBuiltIn = true

    func makeViewController(context: PanelContext) -> NSViewController {
        guard let bookmarkStore = context.bookmarkStore else { return NSViewController() }
        let host = SidebarHostController(
            bookmarkStore: bookmarkStore,
            sshConfigWatcher: context.sshConfigWatcher,
            config: context.appConfig
        )
        host.onConnect = { bookmark in
            context.tabContainer()?.openSSHConnection(bookmark: bookmark)
        }
        host.onNewConnection = {
            guard let window = context.tabContainer()?.view.window else { return }
            NotificationCenter.default.post(name: .simpletonShowNewConnection, object: window)
        }
        return host
    }
}

// MARK: - AI Chat

final class AIChatPanelDefinition: PanelDefinition {
    let id = "ai-chat"
    let name = "AI Chat"
    let icon = "sparkles"
    let description = "AI-powered terminal assistant"
    let defaultSide = PanelSide.right
    let isBuiltIn = true

    func makeViewController(context: PanelContext) -> NSViewController {
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
        vc.onDismiss = nil  // Panel system manages visibility; dismiss button hidden
        return vc
    }
}

// MARK: - Skills (placeholder — replaced in Task 8)

final class SkillsPanelDefinition: PanelDefinition {
    let id = "skills"
    let name = "Skills"
    let icon = "bolt"
    let description = "Run and manage AI skills"
    let defaultSide = PanelSide.right
    let isBuiltIn = true

    func makeViewController(context: PanelContext) -> NSViewController {
        SkillsPanelController(context: context)
    }
}

// MARK: - Notes (placeholder — replaced in Task 6)

final class NotesPanelDefinition: PanelDefinition {
    let id = "notes"
    let name = "Notes"
    let icon = "note.text"
    let description = "Per-directory scratchpad"
    let defaultSide = PanelSide.left
    let isBuiltIn = true

    func makeViewController(context: PanelContext) -> NSViewController {
        NotesPanelController(context: context)
    }
}

// MARK: - Snippets (placeholder — replaced in Task 7)

final class SnippetsPanelDefinition: PanelDefinition {
    let id = "snippets"
    let name = "Snippets"
    let icon = "text.insert"
    let description = "Command templates with placeholders"
    let defaultSide = PanelSide.left
    let isBuiltIn = true

    func makeViewController(context: PanelContext) -> NSViewController {
        SnippetsPanelController(context: context)
    }
}
