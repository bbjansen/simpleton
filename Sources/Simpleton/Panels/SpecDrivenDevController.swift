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
    @Published var board = KanbanBoard()

    /// A generated artifact awaiting approval. While non-nil the view shows the proposed markdown with
    /// Approve/Discard actions; nothing is written to the repo until `approvePending()` runs.
    @Published var pending: PendingArtifact?

    /// A generated-but-unwritten artifact: the target file plus the markdown the AI produced, and the
    /// goal that drove it (used to record a decision on approval).
    struct PendingArtifact: Equatable {
        var artifact: SpecArtifact
        var content: String
        var goal: String
    }

    private let aiService: AIService?
    private let currentPaneProvider: () -> PaneController?
    private let store: SpecWorkspaceStore
    private let skillStore: SkillStore?
    private let memoryStore: MemoryStore?
    private let onOpenFile: (String) -> Void

    init(
        aiService: AIService?,
        currentPaneProvider: @escaping () -> PaneController?,
        store: SpecWorkspaceStore,
        skillStore: SkillStore?,
        memoryStore: MemoryStore?,
        onOpenFile: @escaping (String) -> Void
    ) {
        self.aiService = aiService
        self.currentPaneProvider = currentPaneProvider
        self.store = store
        self.skillStore = skillStore
        self.memoryStore = memoryStore
        self.onOpenFile = onOpenFile
    }

    /// Resolve the project root once the view appears: the git root of the current pane's cwd, else
    /// the cwd itself, else the user's home. Then restore persisted state and load the artifact.
    func start() async {
        projectRoot = resolveProjectRoot()
        memoryStore?.loadForProject(path: projectRoot)
        let state = await store.state(for: projectRoot)
        activeMode = state.activeMode
        activeArtifact = state.activeArtifact
        if activeMode == .board {
            await loadBoard()
        } else {
            await loadArtifact()
        }
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

    /// Ask the AI to write a concise, actionable implementation plan for `goal`. Routed through the
    /// generic generator so it lands in `pending` for approval before `plan.md` is touched.
    func generatePlan(goal: String) async {
        await generate(for: .plan, goal: goal)
    }

    /// Generate the artifact for a doc-producing mode (`brainstorm`, `spec`, `plan`) from `goal`.
    ///
    /// Picks a mode-specific skill's system prompt when one is registered (slug matching the mode),
    /// otherwise the built-in constant; for brainstorm/spec it also injects relevant prior decisions
    /// recalled from `MemoryStore`. The result is staged in `pending` — nothing is written to the repo
    /// until the user approves it.
    func generate(for mode: SpecMode, goal: String) async {
        guard let artifact = mode.generatedArtifact else { return }
        let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let aiService else {
            errorMessage = "AI is not configured. Enable it in Preferences > AI."
            return
        }
        activeMode = mode
        activeArtifact = artifact
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        let system = systemPrompt(for: mode, goal: trimmed)
        let user = "Project root: \(projectRoot)\n\nGoal:\n\(trimmed)"
        let maxTokens = artifact == .brainstorm ? 1800 : 2000
        do {
            let response = try await aiService.complete(
                system: system, user: user, options: AIOptions(maxTokens: maxTokens, temperature: 0.3))
            let markdown = response.trimmingCharacters(in: .whitespacesAndNewlines)
            pending = PendingArtifact(artifact: artifact, content: markdown, goal: trimmed)
            // Surface the proposal in the preview without clobbering the on-disk file yet.
            artifactText = markdown
            isEditing = false
            await persistState()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Write the pending artifact to its repo file and load it. Approving a spec also records a concise
    /// decision back to `MemoryStore` so future generations recall it.
    func approvePending() async {
        guard let pending else { return }
        do {
            try await store.writeArtifact(
                pending.artifact, projectRoot: projectRoot, contents: pending.content)
            if pending.artifact == .spec {
                recordSpecDecision(goal: pending.goal)
            }
            self.pending = nil
            activeArtifact = pending.artifact
            await loadArtifact()
            errorMessage = nil
        } catch {
            errorMessage =
                "Could not write \(pending.artifact.fileName): \(error.localizedDescription)"
        }
    }

    /// Drop the pending proposal without writing anything, restoring the on-disk artifact in the view.
    func discardPending() async {
        pending = nil
        await loadArtifact()
    }

    /// Resolve the system prompt for a mode: a matching skill's prompt if present, else the constant.
    /// For brainstorm/spec, prepend any relevant prior decisions recalled from memory.
    private func systemPrompt(for mode: SpecMode, goal: String) -> String {
        let base = skillStore?.skill(forSlug: mode.rawValue)?.systemPrompt ?? Self.constantPrompt(for: mode)
        guard mode == .brainstorm || mode == .spec else { return base }
        let recall = recalledContext(for: goal)
        return recall.isEmpty ? base : base + "\n\n" + recall
    }

    /// Default built-in system prompt for a doc-generating mode.
    private static func constantPrompt(for mode: SpecMode) -> String {
        switch mode {
        case .brainstorm: return brainstormSystemPrompt
        case .spec: return specSystemPrompt
        case .plan: return planSystemPrompt
        case .act, .board: return ""
        }
    }

    /// A short "Relevant prior decisions/conventions" block built from the top memory hits for `goal`,
    /// or "" when nothing relevant is stored.
    private func recalledContext(for goal: String) -> String {
        guard let memoryStore else { return "" }
        let hits = memoryStore.query(goal, topK: 4, threshold: 0.28)
        guard !hits.isEmpty else { return "" }
        let bullets = hits.map { "- \($0.promptSummary)" }.joined(separator: "\n")
        return """
            Relevant prior decisions/conventions from this project (honor them unless the goal \
            overrides):
            \(bullets)
            """
    }

    /// Save a concise decision entry summarizing an approved spec so later work recalls it.
    private func recordSpecDecision(goal: String) {
        let summary = "Spec approved for: \(goal)"
        _ = memoryStore?.addMemory(content: summary, type: .decision, tags: ["spec", "spec-dev"])
    }

    /// Switch the active mode and persist the choice. Discards any unapproved proposal, points the
    /// active artifact at the mode's displayed artifact, and loads it (board loads the kanban).
    func setMode(_ mode: SpecMode) async {
        guard mode != activeMode else { return }
        activeMode = mode
        pending = nil
        isEditing = false
        if mode == .board {
            activeArtifact = .board
            await loadBoard()
        } else {
            activeArtifact = mode.displayedArtifact
            await loadArtifact()
        }
        await persistState()
    }

    // MARK: - Board (kanban over board.md)

    /// Read `board.md` from disk and parse it into `board`.
    func loadBoard() async {
        let markdown = await store.readArtifact(.board, projectRoot: projectRoot)
        board = BoardMarkdown.parse(markdown)
    }

    /// Serialize `board` and write it back to `board.md`.
    func saveBoard() async {
        do {
            try await store.writeArtifact(
                .board, projectRoot: projectRoot, contents: BoardMarkdown.serialize(board))
            errorMessage = nil
        } catch {
            errorMessage = "Could not save board.md: \(error.localizedDescription)"
        }
    }

    /// Move a card to another column in-memory, then persist the whole board to `board.md`.
    func moveCard(_ card: KanbanCard, to kind: KanbanColumnKind) async {
        board.moveCard(id: card.id, to: kind)
        await saveBoard()
    }

    /// Toggle a card's done state in-memory, then persist to `board.md`.
    func toggleCard(_ card: KanbanCard) async {
        board.toggleCard(id: card.id)
        await saveBoard()
    }

    /// Ask the AI for a task list for `goal`, write it to `board.md` (tasks land in Backlog/Todo), and
    /// reload the board. The quick path for Board mode, mirroring `generatePlan` for Plan mode.
    func generateTasks(goal: String) async {
        let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let aiService else {
            errorMessage = "AI is not configured. Enable it in Preferences > AI."
            return
        }
        activeMode = .board
        activeArtifact = .board
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        let user = "Project root: \(projectRoot)\n\nGoal:\n\(trimmed)"
        do {
            let response = try await aiService.complete(
                system: Self.taskSystemPrompt, user: user, options: AIOptions(maxTokens: 1500, temperature: 0.2))
            let markdown = response.trimmingCharacters(in: .whitespacesAndNewlines)
            // Normalize through the parser so unexpected AI formatting still yields a canonical board.
            let normalized = BoardMarkdown.serialize(BoardMarkdown.parse(markdown))
            try await store.writeArtifact(.board, projectRoot: projectRoot, contents: normalized)
            board = BoardMarkdown.parse(normalized)
            await persistState()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Open a code reference (`path:line`) detected in the artifact preview. Resolves the path against
    /// the project root and inserts an editor command into the active pane, e.g.
    /// `${EDITOR:-vi} <file> +<line>`, letting the user open it in their configured editor.
    func openCodeRef(path: String, line: Int) {
        // Security: the path can arrive out-of-band — a crafted markdown link using the custom code-ref
        // URL scheme bypasses the detector regex. Reject anything with control bytes or shell/terminal
        // metacharacters before composing a command for the pane, so a malicious reference cannot inject
        // terminal control characters or extra commands. See CodeRefLinkParser.isSafePath.
        guard CodeRefLinkParser.isSafePath(path), line >= 1 else {
            errorMessage = "Ignored an unsafe code reference."
            return
        }
        let resolved = CodeRefLinkParser.resolvedPath(path: path, projectRoot: projectRoot)
        let quoted = Self.shellQuote(resolved)
        onOpenFile("${EDITOR:-vi} \(quoted) +\(line)")
    }

    /// Single-quote a path for safe insertion into a shell command line.
    private static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
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

    static let brainstormSystemPrompt = """
        You are a thoughtful product-minded engineer helping a developer brainstorm.
        Output ONLY Markdown — no preamble, no closing remarks, no code fences around the whole document.
        Explore the idea broadly and openly: list possible approaches, trade-offs, open questions, and \
        risks. Use short `## ` sections (e.g. `## Approaches`, `## Open questions`, `## Risks`) with \
        bullet points. Favor breadth over commitment — do not prescribe a single plan yet. When you \
        reference existing code, cite it as `path/to/File.ext:line` so it can be opened directly.
        """

    static let specSystemPrompt = """
        You are a senior software engineer writing a concise requirements specification for a developer.
        Output ONLY Markdown — no preamble, no closing remarks, no code fences around the whole document.
        Structure it with these `## ` sections in order: `## Summary`, `## Requirements`, \
        `## Acceptance criteria`, `## Out of scope`. List requirements and acceptance criteria as \
        bullet points; make acceptance criteria specific and verifiable. Do not invent requirements \
        beyond the stated goal. When you reference existing code, cite it as `path/to/File.ext:line`.
        """

    static let planSystemPrompt = """
        You are a senior software engineer writing an implementation plan for a developer.
        Output ONLY a concise, actionable Markdown implementation plan — no preamble, no closing \
        remarks, no code fences around the whole document.
        Structure it as numbered phases (## Phase 1: ..., ## Phase 2: ...). Under each phase, list \
        concrete tasks as GitHub-style checkboxes: `- [ ] task`.
        Keep tasks small, specific, and verifiable. Prefer the fewest phases that fully deliver the \
        goal. Do not invent requirements beyond the stated goal.
        """

    static let taskSystemPrompt = """
        You are a senior software engineer breaking a goal into a kanban task list for a developer.
        Output ONLY Markdown with exactly these four section headings, in this order, and nothing else: \
        `## Backlog`, `## Todo`, `## In Progress`, `## Done`.
        Under each heading, list tasks as GitHub-style checkboxes: `- [ ] task`. Put every task in \
        `## Backlog` or `## Todo` (leave `## In Progress` and `## Done` empty). Keep tasks small, \
        specific, and verifiable. No preamble, no closing remarks, no code fences.
        """
}

/// NSViewController host for the Spec-Driven Dev panel. Caches its `SpecDrivenDevModel` and hosts
/// `SpecDrivenDevView` via a menu-passthrough hosting view (mirrors `AIChatPanelController`).
final class SpecDrivenDevController: NSViewController {
    private let model: SpecDrivenDevModel

    init(
        aiService: AIService?,
        currentPaneProvider: @escaping () -> PaneController?,
        store: SpecWorkspaceStore,
        skillStore: SkillStore?,
        memoryStore: MemoryStore?,
        onOpenFile: @escaping (String) -> Void
    ) {
        self.model = SpecDrivenDevModel(
            aiService: aiService,
            currentPaneProvider: currentPaneProvider,
            store: store,
            skillStore: skillStore,
            memoryStore: memoryStore,
            onOpenFile: onOpenFile
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        self.view = MenuPassthroughHostingView(rootView: SpecDrivenDevView(model: model))
        self.view.frame = NSRect(x: 0, y: 0, width: 320, height: 600)
    }
}
