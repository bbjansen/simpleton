// Sources/SimpletonCore/Models/KanbanBoard.swift
import Foundation

/// The four fixed columns of the spec-driven-dev kanban board, in canonical left-to-right order.
///
/// `displayName` is the UI label; `heading` is what `BoardMarkdown` emits as a `## ` section title in
/// `board.md`. Parsing maps headings back to columns case-insensitively, so a hand-edited or
/// AI-written `board.md` using any casing still lands in the right column.
public enum KanbanColumnKind: String, Codable, CaseIterable, Sendable {
    case backlog
    case todo
    case inProgress
    case done

    /// Human-readable label for a column header.
    public var displayName: String {
        switch self {
        case .backlog: return "Backlog"
        case .todo: return "Todo"
        case .inProgress: return "In Progress"
        case .done: return "Done"
        }
    }

    /// The markdown `## ` heading text for this column.
    public var heading: String { displayName }

    /// Resolve a markdown heading (case-insensitive, whitespace-trimmed) to a known column.
    /// Unknown headings fall back to `.backlog` so no cards are ever dropped on parse.
    public static func fromHeading(_ raw: String) -> KanbanColumnKind {
        let normalized = raw.trimmingCharacters(in: .whitespaces).lowercased()
        for kind in allCases where kind.displayName.lowercased() == normalized {
            return kind
        }
        return .backlog
    }
}

/// A single kanban card parsed from a `- [ ] title` / `- [x] title` markdown checkbox line, with any
/// indented continuation lines captured as `notes`.
///
/// `id` is a UUID string generated at parse time. It exists only to drive SwiftUI identity and
/// drag-and-drop payloads; it is intentionally not serialized into `board.md` (the markdown stays a
/// clean, hand-editable checklist).
public struct KanbanCard: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var done: Bool
    public var notes: String?

    public init(id: String = UUID().uuidString, title: String, done: Bool = false, notes: String? = nil) {
        self.id = id
        self.title = title
        self.done = done
        self.notes = notes
    }
}

/// An ordered kanban board: the four canonical columns, each with its cards. Columns are always
/// present and always in canonical order, even when empty, so the UI and serializer have a stable
/// shape to render.
public struct KanbanBoard: Equatable, Sendable {
    /// Columns in canonical order. Each entry pairs a column kind with its ordered cards.
    public var columns: [(kind: KanbanColumnKind, cards: [KanbanCard])]

    /// An empty board with all four canonical columns present and no cards.
    public init() {
        columns = KanbanColumnKind.allCases.map { ($0, []) }
    }

    /// Build a board from a per-column card mapping, normalizing to the four canonical columns in
    /// canonical order (missing columns become empty, extras are ignored).
    public init(cardsByColumn: [KanbanColumnKind: [KanbanCard]]) {
        columns = KanbanColumnKind.allCases.map { ($0, cardsByColumn[$0] ?? []) }
    }

    /// The cards currently in a column.
    public func cards(in kind: KanbanColumnKind) -> [KanbanCard] {
        columns.first { $0.kind == kind }?.cards ?? []
    }

    public static func == (lhs: KanbanBoard, rhs: KanbanBoard) -> Bool {
        guard lhs.columns.count == rhs.columns.count else { return false }
        for (left, right) in zip(lhs.columns, rhs.columns) {
            if left.kind != right.kind || left.cards != right.cards { return false }
        }
        return true
    }

    /// Move the card with `cardID` into `destination`, appending it there. A card whose destination is
    /// `.done` is marked done; moving it out of `.done` clears done — keeping the checkbox state and
    /// the column consistent. No-op if the card is not found.
    public mutating func moveCard(id cardID: String, to destination: KanbanColumnKind) {
        var moved: KanbanCard?
        for index in columns.indices {
            if let cardIndex = columns[index].cards.firstIndex(where: { $0.id == cardID }) {
                moved = columns[index].cards.remove(at: cardIndex)
                break
            }
        }
        guard var card = moved else { return }
        card.done = (destination == .done)
        for index in columns.indices where columns[index].kind == destination {
            columns[index].cards.append(card)
            return
        }
    }

    /// Toggle the `done` flag of the card with `cardID` in place. No-op if not found.
    public mutating func toggleCard(id cardID: String) {
        for index in columns.indices {
            if let cardIndex = columns[index].cards.firstIndex(where: { $0.id == cardID }) {
                columns[index].cards[cardIndex].done.toggle()
                return
            }
        }
    }
}

/// Markdown (de)serialization for `board.md`.
///
/// Format: `## <Column>` headings open a column (mapped case-insensitively to the four known
/// columns; unknown headings route to Backlog). `- [ ] title` / `- [x] title` lines are cards.
/// Lines indented beneath a card (two-or-more spaces or a tab) become that card's `notes`.
/// `serialize` always emits the four columns in canonical order, even when empty, so
/// `serialize(parse(x))` is stable for canonical input.
public enum BoardMarkdown {
    /// Parse `board.md` markdown into a `KanbanBoard`.
    public static func parse(_ md: String) -> KanbanBoard {
        var cardsByColumn: [KanbanColumnKind: [KanbanCard]] = [:]
        var currentColumn: KanbanColumnKind = .backlog
        var noteLines: [String] = []

        func flushNotes(into column: KanbanColumnKind) {
            guard !noteLines.isEmpty else { return }
            guard var cards = cardsByColumn[column], !cards.isEmpty else {
                noteLines.removeAll()
                return
            }
            let joined = noteLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                let existing = cards[cards.count - 1].notes
                cards[cards.count - 1].notes = existing.map { "\($0)\n\(joined)" } ?? joined
                cardsByColumn[column] = cards
            }
            noteLines.removeAll()
        }

        for rawLine in md.components(separatedBy: "\n") {
            if let heading = headingText(rawLine) {
                flushNotes(into: currentColumn)
                currentColumn = KanbanColumnKind.fromHeading(heading)
                continue
            }
            if let (done, title) = checkboxItem(rawLine) {
                flushNotes(into: currentColumn)
                var cards = cardsByColumn[currentColumn] ?? []
                cards.append(KanbanCard(title: title, done: done))
                cardsByColumn[currentColumn] = cards
                continue
            }
            // Indented continuation beneath a card → accumulate as notes.
            if isIndentedContinuation(rawLine) {
                noteLines.append(rawLine.trimmingCharacters(in: .whitespaces))
            } else if rawLine.trimmingCharacters(in: .whitespaces).isEmpty {
                // Blank line: keep separation inside a note block if one is open.
                if !noteLines.isEmpty { noteLines.append("") }
            }
        }
        flushNotes(into: currentColumn)
        return KanbanBoard(cardsByColumn: cardsByColumn)
    }

    /// Serialize a board back to canonical `board.md` markdown.
    public static func serialize(_ board: KanbanBoard) -> String {
        var out: [String] = []
        for kind in KanbanColumnKind.allCases {
            out.append("## \(kind.heading)")
            for card in board.cards(in: kind) {
                out.append("- [\(card.done ? "x" : " ")] \(card.title)")
                if let notes = card.notes, !notes.isEmpty {
                    for noteLine in notes.components(separatedBy: "\n") {
                        out.append("  \(noteLine)")
                    }
                }
            }
            out.append("")
        }
        // Trim the trailing blank separator so the document ends with a single newline.
        while out.last == "" { out.removeLast() }
        return out.joined(separator: "\n") + "\n"
    }

    // MARK: - Line parsing helpers

    /// The text after a leading `## ` (or `#`/`###`) heading marker, else nil.
    private static func headingText(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        let withoutHashes = trimmed.drop(while: { $0 == "#" })
        guard withoutHashes.first == " " else { return nil }
        return withoutHashes.trimmingCharacters(in: .whitespaces)
    }

    /// Returns `(done, title)` for a `- [ ]` / `- [x]` checkbox line, else nil.
    private static func checkboxItem(_ line: String) -> (Bool, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
            let rest = trimmed.dropFirst(marker.count)
            guard rest.hasPrefix("["), rest.count >= 3 else { return nil }
            let chars = Array(rest)
            guard chars[0] == "[", chars[2] == "]" else { return nil }
            let mark = chars[1]
            let done = (mark == "x" || mark == "X")
            guard done || mark == " " else { return nil }
            let titleStart = rest.index(rest.startIndex, offsetBy: 3)
            let title = rest[titleStart...].trimmingCharacters(in: .whitespaces)
            return (done, title)
        }
        return nil
    }

    /// True when a non-empty line is indented (leading tab or two-plus spaces), marking it as the
    /// continuation/notes of the preceding card.
    private static func isIndentedContinuation(_ line: String) -> Bool {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return line.hasPrefix("\t") || line.hasPrefix("  ")
    }
}
