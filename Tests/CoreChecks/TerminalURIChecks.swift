// Tests/CoreChecks/TerminalURIChecks.swift
import Foundation
import SimpletonCore

func runTerminalURIChecks(_ t: TestRunner) {
    t.suite("TerminalURI.osc7WithHostname") {
        // The actual bug: a file URL with the machine hostname as the authority.
        t.expectEqual(
            TerminalURI.directoryPath(fromOSC7: "file://Bob-Jansen-GKW17FP70V/Users/bob.jansen"),
            "/Users/bob.jansen", "strips scheme + hostname authority")
    }

    t.suite("TerminalURI.osc7NoHost") {
        t.expectEqual(
            TerminalURI.directoryPath(fromOSC7: "file:///Users/bob/projects"),
            "/Users/bob/projects", "empty authority → path")
    }

    t.suite("TerminalURI.osc7PercentDecoded") {
        t.expectEqual(
            TerminalURI.directoryPath(fromOSC7: "file://host/Users/with%20space"),
            "/Users/with space", "percent-decodes the path")
    }

    t.suite("TerminalURI.plainPathUnchanged") {
        t.expectEqual(
            TerminalURI.directoryPath(fromOSC7: "/Users/bob/plain"),
            "/Users/bob/plain", "a plain path is returned unchanged")
    }
}
