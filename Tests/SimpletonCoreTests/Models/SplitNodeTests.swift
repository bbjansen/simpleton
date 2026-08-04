// Tests/SimpletonCoreTests/Models/SplitNodeTests.swift
import XCTest

@testable import SimpletonCore

final class SplitNodeTests: XCTestCase {

    func testSinglePaneRoundTrip() throws {
        let node = SplitNode.pane(UUID())
        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(SplitNode.self, from: data)
        if case .pane = decoded {} else { XCTFail("Expected .pane") }
    }

    func testSplitRoundTrip() throws {
        let node = SplitNode.split(
            direction: .vertical,
            children: [.pane(UUID()), .pane(UUID())],
            ratios: [0.5, 0.5]
        )
        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(SplitNode.self, from: data)
        if case .split(let dir, let children, let ratios) = decoded {
            XCTAssertEqual(dir, .vertical)
            XCTAssertEqual(children.count, 2)
            XCTAssertEqual(ratios, [0.5, 0.5])
        } else {
            XCTFail("Expected .split")
        }
    }

    func testNestedSplitRoundTrip() throws {
        let inner = SplitNode.split(
            direction: .horizontal, children: [.pane(UUID()), .pane(UUID())], ratios: [0.6, 0.4])
        let outer = SplitNode.split(direction: .vertical, children: [.pane(UUID()), inner], ratios: [0.5, 0.5])

        let data = try JSONEncoder().encode(outer)
        let decoded = try JSONDecoder().decode(SplitNode.self, from: data)

        if case .split(_, let children, _) = decoded {
            if case .split(let dir, let innerChildren, _) = children[1] {
                XCTAssertEqual(dir, .horizontal)
                XCTAssertEqual(innerChildren.count, 2)
            } else {
                XCTFail("Expected nested .split")
            }
        } else {
            XCTFail("Expected .split")
        }
    }

    func testAllPaneIDs() {
        let id1 = UUID(), id2 = UUID(), id3 = UUID()
        let tree = SplitNode.split(
            direction: .vertical,
            children: [
                .pane(id1), .split(direction: .horizontal, children: [.pane(id2), .pane(id3)], ratios: [0.5, 0.5]),
            ],
            ratios: [0.5, 0.5]
        )
        let ids = tree.allPaneIDs
        XCTAssertEqual(Set(ids), Set([id1, id2, id3]))
    }

    func testPaneCount() {
        let tree = SplitNode.split(
            direction: .vertical,
            children: [.pane(UUID()), .pane(UUID())],
            ratios: [0.5, 0.5]
        )
        XCTAssertEqual(tree.paneCount, 2)
        XCTAssertEqual(SplitNode.pane(UUID()).paneCount, 1)
    }
}
