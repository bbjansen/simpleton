// Sources/Simpleton/Panels/PanelProfile.swift
import Foundation

/// Which edge the GUI-client drawer docks on.
enum DockEdge: String, Codable, Equatable {
    case bottom, top, trailing
}

struct PanelProfile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var leftPanelIDs: [String]
    var rightPanelIDs: [String]
    var leftActivePanelID: String?
    var rightActivePanelID: String?
    var leftWidth: CGFloat = 240
    var rightWidth: CGFloat = 320
    /// The GUI client panel docked in the edge drawer (nil = drawer closed).
    var bottomActivePanelID: String?
    /// Which edge the drawer sits on.
    var drawerEdge: DockEdge = .bottom
    /// Drawer height (bottom/top) or width (trailing), in points.
    var drawerSize: CGFloat = 260

    init(
        id: UUID = UUID(), name: String, leftPanelIDs: [String] = [], rightPanelIDs: [String] = [],
        leftActivePanelID: String? = nil, rightActivePanelID: String? = nil, leftWidth: CGFloat = 240,
        rightWidth: CGFloat = 320, bottomActivePanelID: String? = nil,
        drawerEdge: DockEdge = .bottom, drawerSize: CGFloat = 260
    ) {
        self.id = id
        self.name = name
        self.leftPanelIDs = leftPanelIDs
        self.rightPanelIDs = rightPanelIDs
        self.leftActivePanelID = leftActivePanelID
        self.rightActivePanelID = rightActivePanelID
        self.leftWidth = leftWidth
        self.rightWidth = rightWidth
        self.bottomActivePanelID = bottomActivePanelID
        self.drawerEdge = drawerEdge
        self.drawerSize = drawerSize
    }

    /// Tolerant decode so profiles.json written before the drawer fields still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        leftPanelIDs = try c.decodeIfPresent([String].self, forKey: .leftPanelIDs) ?? []
        rightPanelIDs = try c.decodeIfPresent([String].self, forKey: .rightPanelIDs) ?? []
        leftActivePanelID = try c.decodeIfPresent(String.self, forKey: .leftActivePanelID)
        rightActivePanelID = try c.decodeIfPresent(String.self, forKey: .rightActivePanelID)
        leftWidth = try c.decodeIfPresent(CGFloat.self, forKey: .leftWidth) ?? 240
        rightWidth = try c.decodeIfPresent(CGFloat.self, forKey: .rightWidth) ?? 320
        bottomActivePanelID = try c.decodeIfPresent(String.self, forKey: .bottomActivePanelID)
        drawerEdge = try c.decodeIfPresent(DockEdge.self, forKey: .drawerEdge) ?? .bottom
        drawerSize = try c.decodeIfPresent(CGFloat.self, forKey: .drawerSize) ?? 260
    }
}

// MARK: - Panel ID Constants

extension PanelProfile {
    enum PanelID {
        static let connections = "connections"
        static let aiChat = "ai-chat"
        static let skills = "skills"
        static let notes = "notes"
        static let snippets = "snippets"
        static let history = "history"
        static let environment = "environment"
        static let fileBrowser = "file-browser"
        static let processes = "processes"
        static let sshTunnels = "ssh-tunnels"
        static let git = "git"
        static let docker = "docker"
        static let sql = "sql"
        static let sftp = "sftp"
        static let dataConnections = "data-connections"
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
        let wasActiveLeft = leftActivePanelID == id
        let wasActiveRight = rightActivePanelID == id

        leftPanelIDs.removeAll { $0 == id }
        rightPanelIDs.removeAll { $0 == id }
        if wasActiveLeft { leftActivePanelID = nil }
        if wasActiveRight { rightActivePanelID = nil }

        if destination == .left {
            leftPanelIDs.append(id)
            if wasActiveRight { leftActivePanelID = id }
        } else {
            rightPanelIDs.append(id)
            if wasActiveLeft { rightActivePanelID = id }
        }
    }

    /// Set (or clear, with nil) the drawer's active GUI panel.
    mutating func setDrawer(id: String?) {
        bottomActivePanelID = id
    }

    /// Close the drawer.
    mutating func closeDrawer() {
        bottomActivePanelID = nil
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
            rightPanelIDs: [],
            leftActivePanelID: "connections",
            rightActivePanelID: nil
        ),
        PanelProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Developer",
            leftPanelIDs: [
                "connections", "data-connections", "snippets", "notes", "history", "environment",
                "file-browser", "processes", "ssh-tunnels",
            ],
            rightPanelIDs: ["sql"],
            leftActivePanelID: "connections",
            rightActivePanelID: nil
        ),
        PanelProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "DevOps",
            leftPanelIDs: ["connections", "notes", "ssh-tunnels", "processes", "git", "docker"],
            rightPanelIDs: [],
            leftActivePanelID: "connections",
            rightActivePanelID: nil
        ),
    ]
}
