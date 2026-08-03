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
}
