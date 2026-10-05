import Foundation
import SimpletonCore

func runBoardMarkdownChecks(_ t: TestRunner) {
    t.suite("KanbanColumnKind headings + mapping") {
        t.expectEqual(KanbanColumnKind.allCases.count, 4, "four columns")
        t.expectEqual(KanbanColumnKind.inProgress.displayName, "In Progress", "in-progress label")
        t.expectEqual(KanbanColumnKind.inProgress.heading, "In Progress", "in-progress heading")
        t.expectEqual(KanbanColumnKind.fromHeading("in progress"), .inProgress, "lowercase maps")
        t.expectEqual(KanbanColumnKind.fromHeading("  TODO "), .todo, "trim + uppercase maps")
        t.expectEqual(KanbanColumnKind.fromHeading("Done"), .done, "done maps")
        t.expectEqual(KanbanColumnKind.fromHeading("Something Else"), .backlog, "unknown → backlog")
    }

    t.suite("BoardMarkdown parse: columns + checkbox state") {
        let md = """
            ## Backlog
            - [ ] research options

            ## Todo
            - [ ] write parser
            - [ ] write tests

            ## In Progress
            - [ ] build view

            ## Done
            - [x] scaffold model
            """
        let board = BoardMarkdown.parse(md)
        t.expectEqual(board.cards(in: .backlog).count, 1, "one backlog card")
        t.expectEqual(board.cards(in: .todo).count, 2, "two todo cards")
        t.expectEqual(board.cards(in: .inProgress).count, 1, "one in-progress card")
        t.expectEqual(board.cards(in: .done).count, 1, "one done card")
        t.expectEqual(board.cards(in: .todo).first?.title, "write parser", "title parsed")
        t.expectEqual(board.cards(in: .done).first?.done, true, "checked box → done")
        t.expectEqual(board.cards(in: .backlog).first?.done, false, "empty box → not done")
    }

    t.suite("BoardMarkdown parse: case-insensitive headings + unknown → backlog") {
        let md = """
            ## todo
            - [ ] lower heading

            ## Mystery
            - [ ] orphaned
            """
        let board = BoardMarkdown.parse(md)
        t.expectEqual(board.cards(in: .todo).count, 1, "lowercase heading routed to todo")
        t.expectEqual(board.cards(in: .backlog).count, 1, "unknown heading routed to backlog")
    }

    t.suite("BoardMarkdown parse: indented notes") {
        let md = """
            ## Todo
            - [ ] ship feature
              needs design review
              and QA
            - [ ] second task
            """
        let board = BoardMarkdown.parse(md)
        t.expectEqual(board.cards(in: .todo).count, 2, "two tasks")
        t.expectEqual(
            board.cards(in: .todo).first?.notes, "needs design review\nand QA", "notes captured")
        t.expect(board.cards(in: .todo).last?.notes == nil, "second task has no notes")
    }

    t.suite("BoardMarkdown serialize: empty board emits all four columns") {
        let serialized = BoardMarkdown.serialize(KanbanBoard())
        let expected = "## Backlog\n\n## Todo\n\n## In Progress\n\n## Done\n"
        t.expectEqual(serialized, expected, "empty board serialization")
    }

    t.suite("BoardMarkdown round-trip stability") {
        let canonical = """
            ## Backlog
            - [ ] research options

            ## Todo
            - [ ] write parser

            ## In Progress

            ## Done
            - [x] scaffold model
              shipped early

            """
        let once = BoardMarkdown.serialize(BoardMarkdown.parse(canonical))
        let twice = BoardMarkdown.serialize(BoardMarkdown.parse(once))
        t.expectEqual(once, twice, "serialize(parse(x)) is stable")
        let reparsed = BoardMarkdown.parse(once)
        t.expectEqual(reparsed.cards(in: .done).first?.notes, "shipped early", "notes survive round-trip")
        t.expectEqual(reparsed.cards(in: .done).first?.done, true, "done survives round-trip")
    }

    t.suite("KanbanBoard moveCard + toggleCard") {
        var board = BoardMarkdown.parse("## Todo\n- [ ] alpha\n")
        guard let card = board.cards(in: .todo).first else {
            t.expect(false, "expected a todo card")
            return
        }
        board.moveCard(id: card.id, to: .done)
        t.expectEqual(board.cards(in: .todo).count, 0, "card left todo")
        t.expectEqual(board.cards(in: .done).count, 1, "card entered done")
        t.expectEqual(board.cards(in: .done).first?.done, true, "move to done marks done")

        board.moveCard(id: card.id, to: .todo)
        t.expectEqual(board.cards(in: .todo).first?.done, false, "move out of done clears done")

        board.toggleCard(id: card.id)
        t.expectEqual(board.cards(in: .todo).first?.done, true, "toggle flips done")
    }
}
