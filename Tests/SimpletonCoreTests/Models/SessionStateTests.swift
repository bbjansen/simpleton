// Tests/SimpletonCoreTests/Models/SessionStateTests.swift
import XCTest
@testable import SimpletonCore

final class SessionStateTests: XCTestCase {

    func testSessionStateRoundTrip() throws {
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

        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.state.cleanShutdown, false)
        XCTAssertEqual(decoded.state.windows.count, 1)
        XCTAssertEqual(decoded.state.windows[0].tabs.count, 1)
    }

    func testWorkspaceRoundTrip() throws {
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

        XCTAssertEqual(decoded.workspace.name, "Production")
        XCTAssertEqual(decoded.workspace.window.tabs[0].title, "servers")
    }
}
