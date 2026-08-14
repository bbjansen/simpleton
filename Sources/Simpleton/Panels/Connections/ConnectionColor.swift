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
    /// Posted (object = connection `id: UUID`) to open that connection as a text (CLI) client pane.
    static let simpletonOpenConnectionText = Notification.Name("simpletonOpenConnectionText")
    /// Posted (no object) from the drawer SQL panel's Expand button to open the full SQL workspace
    /// window on the same shared `SQLPanelModel`. `AppDelegate` resolves the active tab's cached
    /// `SQLPanelController` and opens (or focuses) a standalone workspace `NSWindow`.
    static let simpletonExpandSQLWorkspace = Notification.Name("simpletonExpandSQLWorkspace")
}
