// Sources/Simpleton/AI/Tools/SpecWorkspaceTools.swift
import Foundation
import SimpletonCore

/// Exposes the spec-driven-dev workspace to the app's own AI agent: reading the repo-local `.plan/*.md`
/// artifacts and driving the kanban board in `board.md`. This is the in-app tool seam (not an external
/// MCP server) — it lets the agent inspect the brainstorm/spec/plan and add or move board tasks using
/// the same `SpecWorkspaceStore` / `BoardMarkdown` machinery the panel uses, so mutations stay
/// canonical and round-trip cleanly.
struct SpecWorkspaceTools: ToolHandler {
    static let handledTools: Set<String> = [
        "spec_read", "board_list", "board_add_task", "board_set_status",
    ]

    private let store = SpecWorkspaceStore()

    func handle(name: String, args: [String: Any], context: ToolContext) async -> String {
        let root = Self.resolveProjectRoot(context: context)
        switch name {
        case "spec_read":
            return await handleSpecRead(args, root: root)
        case "board_list":
            return await handleBoardList(root: root)
        case "board_add_task":
            return await handleBoardAddTask(args, root: root)
        case "board_set_status":
            return await handleBoardSetStatus(args, root: root)
        default:
            return "Unknown spec tool: \(name)"
        }
    }

    // MARK: - spec_read

    private func handleSpecRead(_ args: [String: Any], root: String) async -> String {
        guard let raw = args["artifact"] as? String else {
            return "Missing 'artifact' parameter. Use one of: brainstorm, spec, plan, board."
        }
        guard let artifact = SpecArtifact(rawValue: raw.trimmingCharacters(in: .whitespaces).lowercased())
        else {
            return "Unknown artifact '\(raw)'. Use one of: brainstorm, spec, plan, board."
        }
        let content = await store.readArtifact(artifact, projectRoot: root)
        if content.isEmpty {
            return "[\(artifact.fileName) is empty or does not exist yet under \(root)/.plan/]"
        }
        return content
    }

    // MARK: - board_list

    private func handleBoardList(root: String) async -> String {
        let board = await loadBoard(root: root)
        var lines: [String] = []
        for column in board.columns {
            lines.append("## \(column.kind.displayName) (\(column.cards.count))")
            if column.cards.isEmpty {
                lines.append("  (empty)")
            } else {
                for card in column.cards {
                    lines.append("  - [\(card.done ? "x" : " ")] \(card.title)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - board_add_task

    private func handleBoardAddTask(_ args: [String: Any], root: String) async -> String {
        guard let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !title.isEmpty
        else {
            return "Missing 'title' parameter."
        }
        let column: KanbanColumnKind
        if let rawColumn = args["column"] as? String, !rawColumn.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let resolved = Self.parseColumn(rawColumn) else {
                return Self.invalidColumnMessage(rawColumn)
            }
            column = resolved
        } else {
            column = .backlog
        }

        var board = await loadBoard(root: root)
        board.addCard(title: title, to: column)
        do {
            try await saveBoard(board, root: root)
        } catch {
            return "Error writing board.md: \(error.localizedDescription)"
        }
        return "Added task '\(title)' to \(column.displayName)."
    }

    // MARK: - board_set_status

    private func handleBoardSetStatus(_ args: [String: Any], root: String) async -> String {
        guard let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !title.isEmpty
        else {
            return "Missing 'title' parameter."
        }
        guard let rawColumn = args["column"] as? String else {
            return "Missing 'column' parameter. Use one of: Backlog, Todo, In Progress, Done."
        }
        guard let column = Self.parseColumn(rawColumn) else {
            return Self.invalidColumnMessage(rawColumn)
        }

        var board = await loadBoard(root: root)
        guard board.moveCard(titled: title, to: column) else {
            return "No task matching '\(title)' found on the board."
        }
        do {
            try await saveBoard(board, root: root)
        } catch {
            return "Error writing board.md: \(error.localizedDescription)"
        }
        return "Moved task '\(title)' to \(column.displayName)."
    }

    // MARK: - Board IO helpers

    private func loadBoard(root: String) async -> KanbanBoard {
        let markdown = await store.readArtifact(.board, projectRoot: root)
        return BoardMarkdown.parse(markdown)
    }

    private func saveBoard(_ board: KanbanBoard, root: String) async throws {
        try await store.writeArtifact(.board, projectRoot: root, contents: BoardMarkdown.serialize(board))
    }

    // MARK: - Shared helpers

    /// Resolve a column name against the four canonical columns (case-insensitive, whitespace-trimmed),
    /// returning nil for anything that is not an exact known label — so an invalid value surfaces a
    /// clear error instead of silently landing in Backlog (which `fromHeading` would do).
    private static func parseColumn(_ raw: String) -> KanbanColumnKind? {
        let normalized = raw.trimmingCharacters(in: .whitespaces).lowercased()
        return KanbanColumnKind.allCases.first { $0.displayName.lowercased() == normalized }
    }

    private static func invalidColumnMessage(_ raw: String) -> String {
        "Unknown column '\(raw)'. Use one of: Backlog, Todo, In Progress, Done."
    }

    /// The project root: the git top-level of the focused pane's cwd, else that cwd, else the home
    /// directory — mirroring how `SpecDrivenDevModel` resolves it so the agent and the panel agree.
    private static func resolveProjectRoot(context: ToolContext) -> String {
        if let cwd = context.focusedPane.currentDirectory, !cwd.isEmpty {
            return gitRoot(of: cwd) ?? cwd
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// The git top-level of `cwd`, if `cwd` is inside a repo; otherwise nil.
    private static func gitRoot(of cwd: String) -> String? {
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
}
