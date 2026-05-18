// Sources/Simpleton/AICoordinator.swift
import AppKit
import SwiftTerm
import SimpletonCore

final class AICoordinator {

    private let aiService: () -> AIService?
    private let aiExplainPanel: () -> AIExplainPanel?
    private let activeSplitController: () -> SplitController?
    private let windowControllers: () -> [WindowController]

    init(
        aiService: @escaping () -> AIService?,
        aiExplainPanel: @escaping () -> AIExplainPanel?,
        activeSplitController: @escaping () -> SplitController?,
        windowControllers: @escaping () -> [WindowController]
    ) {
        self.aiService = aiService
        self.aiExplainPanel = aiExplainPanel
        self.activeSplitController = activeSplitController
        self.windowControllers = windowControllers
    }

    func toggleAIChat() {
        NotificationCenter.default.post(name: .simpletonToggleAIChat, object: aiService())
    }

    func showSkillPicker() {
        guard let ai = aiService(), ai.isEnabled else { return }
        NotificationCenter.default.post(name: .simpletonRunSkillPicker, object: ai)
    }

    func explainSelection() {
        guard let ai = aiService(), ai.isEnabled,
              let sc = activeSplitController(),
              let pane = sc.panes[sc.focusedPaneID] else { return }

        let selected = pane.terminalView.getSelection() ?? ""
        guard !selected.isEmpty else { return }

        aiExplainPanel()?.show(
            title: "Explain Selection",
            aiService: ai,
            system: "You are a helpful terminal assistant. Explain the following terminal output or command concisely.",
            user: selected,
            relativeTo: NSApp.keyWindow
        )
    }

    func explainLastError() {
        guard let ai = aiService(), ai.isEnabled,
              let sc = activeSplitController(),
              let pane = sc.panes[sc.focusedPaneID] else { return }

        let context = AIContextBuilder.build(terminalView: pane.terminalView, recentOutputLines: 50)
        let output = context.recentOutput ?? "(no output captured)"

        aiExplainPanel()?.show(
            title: "Explain Error",
            aiService: ai,
            system: "You are a helpful terminal assistant. Explain this error and suggest a fix. Be concise.",
            user: "The command failed. Here is the recent terminal output:\n\n\(output)",
            relativeTo: NSApp.keyWindow
        )
    }

    func handleExplainError(paneID: PaneID) {
        guard let ai = aiService(), ai.isEnabled else { return }

        for wc in windowControllers() {
            guard let tabContainer = wc.window?.contentViewController as? TabContainerController,
                  let pane = tabContainer.splitController.panes[paneID] else { continue }

            let context = AIContextBuilder.build(terminalView: pane.terminalView, recentOutputLines: 50)
            let output = context.recentOutput ?? "(no output captured)"

            aiExplainPanel()?.show(
                title: "Explain Error",
                aiService: ai,
                system: "You are a helpful terminal assistant. Explain this error and suggest a fix. Be concise.",
                user: "The command failed. Here is the recent terminal output:\n\n\(output)",
                relativeTo: pane.terminalView.window
            )
            break
        }
    }

    func saveAIConfig(_ config: AIConfig) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let simpletonDir = appSupport.appendingPathComponent("Simpleton")
        let aiConfigFile = simpletonDir.appendingPathComponent("ai-config.json")
        do {
            let data = try JSONEncoder().encode(AIConfigFile(config: config))
            try data.write(to: aiConfigFile)
        } catch {
            print("[Simpleton] Failed to save AI config: \(error)")
        }
    }
}
