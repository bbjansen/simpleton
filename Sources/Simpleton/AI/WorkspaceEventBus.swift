// Sources/Simpleton/AI/WorkspaceEventBus.swift
import Foundation

struct WorkspaceEvent: Identifiable {
    let id: UUID
    let timestamp: Date
    let tabID: UUID
    let paneLabel: String
    let type: EventType

    enum EventType {
        case commandCompleted(cmd: String, exitCode: Int32, outputSnippet: String)
        case directoryChanged(path: String)
    }
}

final class WorkspaceEventBus {
    private var events: [WorkspaceEvent] = []
    private let maxEvents = 50
    private let lock = NSLock()

    func publish(_ event: WorkspaceEvent) {
        lock.lock()
        defer { lock.unlock() }
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }

    func recentEvents(excludingTab tabID: UUID, limit: Int = 5) -> [WorkspaceEvent] {
        lock.lock()
        defer { lock.unlock() }
        return Array(
            events
                .filter { $0.tabID != tabID }
                .suffix(limit)
        )
    }

    func formatForPrompt(excludingTab tabID: UUID) -> String? {
        let recent = recentEvents(excludingTab: tabID, limit: 5)
        guard !recent.isEmpty else { return nil }

        let now = Date()
        var lines: [String] = ["## Recent activity in other tabs"]
        for event in recent {
            let ago = Self.relativeTime(from: event.timestamp, to: now)
            let label = event.paneLabel
            switch event.type {
            case .commandCompleted(let cmd, let exitCode, let snippet):
                let truncated = snippet.count > 80 ? String(snippet.prefix(80)) + "..." : snippet
                let detail = truncated.isEmpty ? "" : " (\(truncated))"
                lines.append("- [\(label), \(ago)] `\(cmd)` \u{2192} exit \(exitCode)\(detail)")
            case .directoryChanged(let path):
                lines.append("- [\(label), \(ago)] cd \(path)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func relativeTime(from start: Date, to end: Date) -> String {
        let seconds = Int(end.timeIntervalSince(start))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
    }
}
