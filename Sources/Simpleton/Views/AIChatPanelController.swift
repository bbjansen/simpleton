// Sources/Simpleton/Views/AIChatPanelController.swift
import AppKit
import SwiftUI
import SimpletonCore

/// NSHostingView subclass that lets Cmd+key shortcuts pass through to the menu bar
/// instead of being eaten by SwiftUI TextFields.
final class MenuPassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // If Cmd is held (without Ctrl — Ctrl+Cmd combos may be used by terminal),
        // let the menu bar handle it first.
        if event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.control) {
            if NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// NSViewController host for the AI Chat Panel.
final class AIChatPanelController: NSViewController {

    private let aiService: AIService
    var contextProvider: (() -> AIContext)?
    var onInsertCommand: ((String) -> Void)?
    var onDismiss: (() -> Void)?
    var skillStore: SkillStore?
    var memoryStore: MemoryStore?
    var projectIndexer: ProjectIndexer?
    var currentPaneProvider: (() -> PaneController?)?

    /// Per-tab conversation. Set by PanelRegistry.rebindAIChat(to:) when the active tab changes.
    var conversation: TabConversation? {
        didSet { rebuildHostingView() }
    }

    init(aiService: AIService) {
        self.aiService = aiService
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let chatView = buildChatView()
        self.view = MenuPassthroughHostingView(rootView: chatView)
        self.view.frame = NSRect(x: 0, y: 0, width: 320, height: 600)
    }

    private func rebuildHostingView() {
        guard isViewLoaded else { return }
        let chatView = buildChatView()
        if let hostingView = self.view as? MenuPassthroughHostingView<AIChatPanelView> {
            hostingView.rootView = chatView
        }
    }

    private func buildChatView() -> AIChatPanelView {
        var chatView = AIChatPanelView(
            aiService: aiService,
            contextProvider: { [weak self] in self?.contextProvider?() ?? AIContext(os: "macOS", recentCommands: []) },
            onInsertCommand: { [weak self] cmd in self?.onInsertCommand?(cmd) },
            onDismiss: onDismiss.map { _ in { [weak self] in self?.onDismiss?() } }
        )
        chatView.skillStore = skillStore
        chatView.memoryStore = memoryStore
        chatView.projectIndexer = projectIndexer
        chatView.currentPaneProvider = currentPaneProvider
        chatView.conversation = conversation
        return chatView
    }
}
