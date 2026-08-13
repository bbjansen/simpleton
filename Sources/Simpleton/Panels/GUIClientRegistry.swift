// Sources/Simpleton/Panels/GUIClientRegistry.swift
import Foundation
import SimpletonCore

/// Maps a `ConnectionKind` to the panel id of its GUI client, so the Data
/// Connections manager can launch any registered GUI client (not just SQL) and
/// the container can reveal the right drawer panel. GUI-client panels register
/// their kinds at startup (see `AppDelegate`).
@MainActor
final class GUIClientRegistry {
    static let shared = GUIClientRegistry()
    private var map: [ConnectionKind: String] = [:]
    private init() {}

    /// Register a panel id as the GUI client for one or more connection kinds.
    func register(kinds: [ConnectionKind], panelID: String) {
        for kind in kinds { map[kind] = panelID }
    }

    /// The panel id of the GUI client for `kind`, or nil if the kind has no GUI
    /// client (it then launches as a text/CLI client instead).
    func panelID(for kind: ConnectionKind) -> String? { map[kind] }
}

/// One-shot bridge for a `.gui` launch: the connection id and target panel id the
/// launched GUI client should open on its next appearance. Set synchronously
/// *before* posting `.simpletonOpenConnectionGUI`, so every observer (the
/// container that reveals the panel, and the panel itself) sees it regardless of
/// order. The target panel consumes it exactly once via `take(for:)`.
@MainActor
final class PendingClientOpen {
    static let shared = PendingClientOpen()
    var connectionID: UUID?
    var panelID: String?
    private init() {}

    /// If a pending open targets `panelID`, return its connection id and clear
    /// the holder. Returns nil (leaving the holder untouched) for other panels.
    func take(for panelID: String) -> UUID? {
        guard self.panelID == panelID, let id = connectionID else { return nil }
        connectionID = nil
        self.panelID = nil
        return id
    }
}
