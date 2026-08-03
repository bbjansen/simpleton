// Tests/CoreChecks/SplitNodeChecks.swift
// Ported from Tests/SimpletonCoreTests/Models/SplitNodeTests.swift
import Foundation
import SimpletonCore

func runSplitNodeChecks(_ t: TestRunner) {
    t.suite("SplitNode.testSinglePaneRoundTrip") {
        do {
            let node = SplitNode.pane(UUID())
            let data = try JSONEncoder().encode(node)
            let decoded = try JSONDecoder().decode(SplitNode.self, from: data)
            if case .pane = decoded { t.expect(true, "") } else { t.expect(false, "Expected .pane") }
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    t.suite("SplitNode.testSplitRoundTrip") {
        do {
            let node = SplitNode.split(
                direction: .vertical,
                children: [.pane(UUID()), .pane(UUID())],
                ratios: [0.5, 0.5]
            )
            let data = try JSONEncoder().encode(node)
            let decoded = try JSONDecoder().decode(SplitNode.self, from: data)
            if case .split(let dir, let children, let ratios) = decoded {
                t.expectEqual(dir, .vertical, "direction")
                t.expectEqual(children.count, 2, "children count")
                t.expectEqual(ratios, [0.5, 0.5], "ratios")
            } else {
                t.expect(false, "Expected .split")
            }
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    t.suite("SplitNode.testNestedSplitRoundTrip") {
        do {
            let inner = SplitNode.split(direction: .horizontal, children: [.pane(UUID()), .pane(UUID())], ratios: [0.6, 0.4])
            let outer = SplitNode.split(direction: .vertical, children: [.pane(UUID()), inner], ratios: [0.5, 0.5])

            let data = try JSONEncoder().encode(outer)
            let decoded = try JSONDecoder().decode(SplitNode.self, from: data)

            if case .split(_, let children, _) = decoded {
                if case .split(let dir, let innerChildren, _) = children[1] {
                    t.expectEqual(dir, .horizontal, "nested direction")
                    t.expectEqual(innerChildren.count, 2, "nested children count")
                } else { t.expect(false, "Expected nested .split") }
            } else { t.expect(false, "Expected .split") }
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    t.suite("SplitNode.testAllPaneIDs") {
        let id1 = UUID(), id2 = UUID(), id3 = UUID()
        let tree = SplitNode.split(
            direction: .vertical,
            children: [.pane(id1), .split(direction: .horizontal, children: [.pane(id2), .pane(id3)], ratios: [0.5, 0.5])],
            ratios: [0.5, 0.5]
        )
        let ids = tree.allPaneIDs
        t.expectEqual(Set(ids), Set([id1, id2, id3]), "all pane ids collected")
    }

    t.suite("SplitNode.testPaneCount") {
        let tree = SplitNode.split(
            direction: .vertical,
            children: [.pane(UUID()), .pane(UUID())],
            ratios: [0.5, 0.5]
        )
        t.expectEqual(tree.paneCount, 2, "split pane count")
        t.expectEqual(SplitNode.pane(UUID()).paneCount, 1, "single pane count")
    }
}
