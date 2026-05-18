// Sources/Simpleton/Panels/PanelProfile.swift
import Foundation

struct PanelProfile: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var leftPanelIDs: [String]
    var rightPanelIDs: [String]
    var leftActivePanelID: String?
    var rightActivePanelID: String?
    var leftWidth: CGFloat = 240
    var rightWidth: CGFloat = 320
}

// MARK: - Panel ID Constants

extension PanelProfile {
    enum PanelID {
        static let connections = "connections"
        static let aiChat      = "ai-chat"
        static let skills      = "skills"
        static let notes       = "notes"
        static let snippets    = "snippets"
        static let history     = "history"
        static let environment = "environment"
        static let fileBrowser = "file-browser"
        static let processes   = "processes"
        static let sshTunnels  = "ssh-tunnels"
        static let git         = "git"
        static let docker      = "docker"
    }
}

extension PanelProfile {
    /// Reserved UUID for the wizard-created Default profile.
    static let defaultProfileID = UUID(uuidString: "00000000-0000-0000-0001-000000000001")!
}

// MARK: - Mutation Helpers

extension PanelProfile {
    /// Toggles a panel's active state on the given side.
    mutating func togglePanel(id: String, on side: PanelSide) {
        if side == .left {
            leftActivePanelID = (leftActivePanelID == id) ? nil : id
        } else {
            rightActivePanelID = (rightActivePanelID == id) ? nil : id
        }
    }

    /// Moves a panel from whichever side it's on to `destination`, preserving its active state.
    mutating func movePanel(id: String, to destination: PanelSide) {
        let wasActiveLeft  = leftActivePanelID == id
        let wasActiveRight = rightActivePanelID == id

        leftPanelIDs.removeAll  { $0 == id }
        rightPanelIDs.removeAll { $0 == id }
        if wasActiveLeft  { leftActivePanelID  = nil }
        if wasActiveRight { rightActivePanelID = nil }

        if destination == .left {
            leftPanelIDs.append(id)
            if wasActiveRight { leftActivePanelID = id }
        } else {
            rightPanelIDs.append(id)
            if wasActiveLeft { rightActivePanelID = id }
        }
    }

    /// Ensures a panel is present on `side` and sets it as active.
    mutating func activatePanel(id: String, on side: PanelSide) {
        if side == .left {
            if !leftPanelIDs.contains(id) { leftPanelIDs.append(id) }
            leftActivePanelID = id
        } else {
            if !rightPanelIDs.contains(id) { rightPanelIDs.append(id) }
            rightActivePanelID = id
        }
    }
}

extension PanelProfile {
    static let defaultProfiles: [PanelProfile] = [
        PanelProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "General",
            leftPanelIDs: ["connections", "history", "file-browser"],
            rightPanelIDs: ["ai-chat"],
            leftActivePanelID: "connections",
            rightActivePanelID: nil
        ),
        PanelProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Developer",
            leftPanelIDs: ["connections", "snippets", "notes", "history", "environment", "file-browser", "processes", "ssh-tunnels"],
            rightPanelIDs: ["ai-chat"],
            leftActivePanelID: "connections",
            rightActivePanelID: "ai-chat"
        ),
        PanelProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "DevOps",
            leftPanelIDs: ["connections", "notes", "ssh-tunnels", "processes", "git", "docker"],
            rightPanelIDs: ["ai-chat"],
            leftActivePanelID: "connections",
            rightActivePanelID: nil
        ),
    ]
}
