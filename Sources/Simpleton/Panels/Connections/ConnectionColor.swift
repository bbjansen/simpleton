// Sources/Simpleton/Panels/Connections/ConnectionColor.swift
import SwiftUI

/// The env-safety color palette for data connections — the app's 8 accent names → SwiftUI colors.
enum ConnectionColor {
    static let names = ["red", "orange", "yellow", "green", "blue", "purple", "pink", "graphite"]

    static func swatch(_ name: String?) -> Color {
        switch name {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "graphite": return Color(nsColor: .systemGray)
        default: return DT.textFaint
        }
    }
}

/// How a connection is launched from the manager.
enum ConnectionLaunch { case gui, text }

extension Notification.Name {
    /// Posted (object = connection `id: UUID`) to reveal the SQL panel and open that connection.
    static let simpletonOpenConnectionGUI = Notification.Name("simpletonOpenConnectionGUI")
}

/// One-shot bridge for a `.gui` launch: the connection id the SQL panel should open on its next
/// appearance. Set synchronously *before* posting `.simpletonOpenConnectionGUI`, so every observer
/// (the container that reveals/mounts the panel, and the panel itself) sees it regardless of order.
/// The panel consumes it exactly once (clears on read), so a cold mount and a warm notification never
/// double-open.
@MainActor
final class SQLPendingOpen {
    static let shared = SQLPendingOpen()
    var connectionID: UUID?
    private init() {}
}
