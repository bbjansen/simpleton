// Tests/CoreChecks/SessionStateChecks.swift
// Ported from Tests/SimpletonCoreTests/Models/SessionStateTests.swift
import Foundation
import SimpletonCore

func runSessionStateChecks(_ t: TestRunner) {
    t.suite("SessionState.testSessionStateRoundTrip") {
        do {
            let paneConn = PaneConnection.local(workingDirectory: "/Users/test")
            let tab = TabState(id: UUID(), title: "local", splitTree: .pane(paneConn: paneConn))
            let window = WindowState(
                id: UUID(),
                frame: WindowFrame(x: 100, y: 100, width: 1200, height: 800),
                workspaceId: nil,
                tabs: [tab]
            )
            let state = SessionState(cleanShutdown: false, windows: [window])
            let file = SessionStateFile(state: state)

            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(file)
            let decoded = try JSONDecoder().decode(SessionStateFile.self, from: data)

            t.expectEqual(decoded.version, 1, "version")
            t.expectEqual(decoded.state.cleanShutdown, false, "cleanShutdown")
            t.expectEqual(decoded.state.windows.count, 1, "windows count")
            t.expectEqual(decoded.state.windows.first?.tabs.count, 1, "tabs count")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    t.suite("SessionState.testWorkspaceRoundTrip") {
        do {
            let tab = TabState(id: UUID(), title: "servers", splitTree: .pane(paneConn: .ssh(bookmarkId: UUID())))
            let workspace = Workspace(
                name: "Production",
                window: WindowState(
                    id: UUID(),
                    frame: WindowFrame(x: 0, y: 0, width: 1400, height: 900),
                    workspaceId: nil,
                    tabs: [tab]
                )
            )
            let file = WorkspaceFile(workspace: workspace)
            let data = try JSONEncoder().encode(file)
            let decoded = try JSONDecoder().decode(WorkspaceFile.self, from: data)

            t.expectEqual(decoded.workspace.name, "Production", "workspace name")
            t.expectEqual(decoded.workspace.window.tabs.first?.title, "servers", "tab title")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    // Restore reconstructs the exact saved layout. These cover the pure transform behind it:
    // SessionSplitNode.materialize — a single pane, a flat N-way split, and a nested tree.
    t.suite("SessionSplitNode.materializeSinglePane") {
        let id = UUID()
        let saved = SessionSplitNode.pane(paneConn: .local(workingDirectory: "/Users/test"))
        let (tree, leaves) = saved.materialize(makeID: { id })

        t.expectEqual(leaves.count, 1, "one leaf")
        t.expectEqual(leaves.first?.id, id, "leaf uses generated id")
        t.expectEqual(leaves.first?.connection, .local(workingDirectory: "/Users/test"), "leaf keeps connection")
        if case .pane(let treeID) = tree {
            t.expectEqual(treeID, id, "tree is a single pane with the generated id")
        } else {
            t.expect(false, "expected a .pane tree")
        }
    }

    t.suite("SessionSplitNode.materializeFlatSplitPreservesOrderAndRatios") {
        var ids: [PaneID] = []
        let saved = SessionSplitNode.split(
            direction: .vertical,
            children: [
                .pane(paneConn: .local(workingDirectory: "/a")),
                .pane(paneConn: .local(workingDirectory: "/b")),
                .pane(paneConn: .local(workingDirectory: "/c")),
            ],
            ratios: [0.2, 0.3, 0.5]
        )
        let (tree, leaves) = saved.materialize(makeID: {
            let id = UUID(); ids.append(id); return id
        })

        t.expectEqual(leaves.count, 3, "three leaves")
        t.expectEqual(
            leaves.map(\.connection),
            [
                .local(workingDirectory: "/a"),
                .local(workingDirectory: "/b"),
                .local(workingDirectory: "/c"),
            ], "leaves preserve left-to-right order")
        if case .split(let dir, let children, let ratios) = tree {
            t.expectEqual(dir, .vertical, "direction preserved")
            t.expectEqual(ratios, [0.2, 0.3, 0.5], "ratios preserved")
            t.expectEqual(children.count, 3, "three children")
            t.expectEqual(tree.allPaneIDs, ids, "child panes reference the generated ids in order")
        } else {
            t.expect(false, "expected a .split tree")
        }
    }

    t.suite("SessionSplitNode.materializeNestedPreservesStructure") {
        let bmID = UUID()
        // horizontal[ pane(/a), vertical[ ssh(bm), pane(/c) ] ] — a split nested inside a split.
        let saved = SessionSplitNode.split(
            direction: .horizontal,
            children: [
                .pane(paneConn: .local(workingDirectory: "/a")),
                .split(
                    direction: .vertical,
                    children: [
                        .pane(paneConn: .ssh(bookmarkId: bmID)),
                        .pane(paneConn: .local(workingDirectory: "/c")),
                    ],
                    ratios: [0.4, 0.6]
                ),
            ],
            ratios: [0.3, 0.7]
        )
        let (tree, leaves) = saved.materialize(makeID: { UUID() })

        // Three leaves, depth-first, connections intact.
        t.expectEqual(leaves.count, 3, "three leaves across the nested tree")
        t.expectEqual(
            leaves.map(\.connection),
            [
                .local(workingDirectory: "/a"),
                .ssh(bookmarkId: bmID),
                .local(workingDirectory: "/c"),
            ], "leaves flattened depth-first with connections intact")
        // All pane IDs unique — no leaf shares an id.
        t.expectEqual(Set(tree.allPaneIDs).count, 3, "all pane ids are unique")

        // The nesting itself survives: outer split holds a pane and an inner split, not three flat panes.
        guard case .split(let outerDir, let outerChildren, let outerRatios) = tree else {
            t.expect(false, "expected an outer .split"); return
        }
        t.expectEqual(outerDir, .horizontal, "outer direction preserved")
        t.expectEqual(outerRatios, [0.3, 0.7], "outer ratios preserved")
        t.expectEqual(outerChildren.count, 2, "outer split has two children (pane + nested split)")
        if case .pane = outerChildren.first {} else { t.expect(false, "first outer child is a pane") }
        guard outerChildren.count == 2, case .split(let innerDir, let innerChildren, let innerRatios) = outerChildren[1]
        else {
            t.expect(false, "second outer child is a nested split"); return
        }
        t.expectEqual(innerDir, .vertical, "inner direction preserved")
        t.expectEqual(innerRatios, [0.4, 0.6], "inner ratios preserved")
        t.expectEqual(innerChildren.count, 2, "inner split has two panes")
    }
}
