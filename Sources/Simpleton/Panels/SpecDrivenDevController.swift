// Sources/Simpleton/Panels/SpecDrivenDevController.swift
import AppKit
import Combine
import SimpletonCore
import SwiftUI

/// Observable model backing the Spec-Driven Dev panel. Owns the resolved project root, the active
/// mode/artifact, the artifact's markdown text, and drives plan generation through `AIService`.
///
/// Phase 1 implements the **Plan** mode end to end (generate `plan.md` from a goal, preview/edit,
/// save). The model is structured so later phases can add brainstorm/spec generation and a kanban
/// view over `board.md` by adding methods here and reading the same artifact files.
@MainActor
final class SpecDrivenDevModel: ObservableObject {
    @Published var activeMode: SpecMode = .plan
    @Published var activeArtifact: SpecArtifact = .plan
    @Published var artifactText: String = ""
    @Published var isGenerating = false
    @Published var isEditing = false
    @Published var projectRoot: String = ""
    @Published var errorMessage: String?

    private let aiService: AIService?
    private let currentPaneProvider: () -> PaneController?
    private let store: SpecWorkspaceStore

    init(
        aiService: AIService?,
        currentPaneProvider: @escaping () -> PaneController?,
        store: SpecWorkspaceStore
    ) {
        self.aiService = aiService
        self.currentPaneProvider = currentPaneProvider
        self.store = store
    }

    /// Resolve the project root once the view appears: the git root of the current pane's cwd, else
    /// the cwd itself, else the user's home. Then restore persisted state and load the artifact.
    func start() async {
        projectRoot = resolveProjectRoot()
        let state = await store.state(for: projectRoot)
        activeMode = state.activeMode
        activeArtifact = state.activeArtifact
        await loadArtifact()
    }

    /// The git top-level of `cwd`, if `cwd` is inside a repo; otherwise nil.
    private func gitRoot(of cwd: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", cwd, "rev-parse", "--show-toplevel"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let root = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return root.isEmpty ? nil : root
        } catch {
            return nil
        }
    }

    private func resolveProjectRoot() -> String {
        if let cwd = currentPaneProvider()?.currentDirectory, !cwd.isEmpty {
            return gitRoot(of: cwd) ?? cwd
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// Reload the active artifact's markdown from disk into `artifactText`.
    func loadArtifact() async {
        artifactText = await store.readArtifact(activeArtifact, projectRoot: projectRoot)
    }

    /// Write `artifactText` back to the active artifact's file under `<root>/.plan/`.
    func saveArtifact() async {
        do {
            try await store.writeArtifact(activeArtifact, projectRoot: projectRoot, contents: artifactText)
            isEditing = false
            errorMessage = nil
        } catch {
            errorMessage = "Could not save \(activeArtifact.fileName): \(error.localizedDescription)"
        }
        await persistState()
    }

    /// Ask the AI to write a concise, actionable implementation plan for `goal`, store it in
    /// `<root>/.plan/plan.md`, and load it into the editor.
    func generatePlan(goal: String) async {
        let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let aiService else {
            errorMessage = "AI is not configured. Enable it in Preferences > AI."
            return
        }
        activeMode = .plan
        activeArtifact = .plan
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        let system = Self.planSystemPrompt
        let user = "Project root: \(projectRoot)\n\nGoal:\n\(trimmed)"
        do {
            let plan = try await aiService.complete(
                system: system, user: user, options: AIOptions(maxTokens: 2000, temperature: 0.2))
            let markdown = plan.trimmingCharacters(in: .whitespacesAndNewlines)
            try await store.writeArtifact(.plan, projectRoot: projectRoot, contents: markdown)
            artifactText = markdown
            isEditing = false
            await persistState()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Switch the active mode and persist the choice.
    func setMode(_ mode: SpecMode) async {
        guard mode != activeMode else { return }
        activeMode = mode
        await persistState()
    }

    private func persistState() async {
        await store.save(
            SpecWorkspaceState(
                activeMode: activeMode, activeArtifact: activeArtifact, projectPath: projectRoot))
    }

    /// The absolute path of the active artifact, for the footer display.
    var artifactPath: String {
        SpecWorkspaceStore.artifactURL(activeArtifact, projectRoot: projectRoot).path
    }

    static let planSystemPrompt = """
        You are a senior software engineer writing an implementation plan for a developer.
        Output ONLY a concise, actionable Markdown implementation plan — no preamble, no closing \
        remarks, no code fences around the whole document.
        Structure it as numbered phases (## Phase 1: ..., ## Phase 2: ...). Under each phase, list \
        concrete tasks as GitHub-style checkboxes: `- [ ] task`.
        Keep tasks small, specific, and verifiable. Prefer the fewest phases that fully deliver the \
        goal. Do not invent requirements beyond the stated goal.
        """
}

/// NSViewController host for the Spec-Driven Dev panel. Caches its `SpecDrivenDevModel` and hosts
/// `SpecDrivenDevView` via a menu-passthrough hosting view (mirrors `AIChatPanelController`).
final class SpecDrivenDevController: NSViewController {
    private let model: SpecDrivenDevModel

    init(aiService: AIService?, currentPaneProvider: @escaping () -> PaneController?, store: SpecWorkspaceStore) {
        self.model = SpecDrivenDevModel(
            aiService: aiService, currentPaneProvider: currentPaneProvider, store: store)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        self.view = MenuPassthroughHostingView(rootView: SpecDrivenDevView(model: model))
        self.view.frame = NSRect(x: 0, y: 0, width: 320, height: 600)
    }
}
