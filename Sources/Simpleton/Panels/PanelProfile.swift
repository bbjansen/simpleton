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

extension PanelProfile {
    static let defaultProfiles: [PanelProfile] = [
        PanelProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "General",
            leftPanelIDs: ["connections"],
            rightPanelIDs: ["ai-chat"],
            leftActivePanelID: nil,
            rightActivePanelID: nil
        ),
        PanelProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Developer",
            leftPanelIDs: ["connections", "snippets"],
            rightPanelIDs: ["ai-chat", "skills"],
            leftActivePanelID: nil,
            rightActivePanelID: "ai-chat"
        ),
        PanelProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "DevOps",
            leftPanelIDs: ["connections", "notes"],
            rightPanelIDs: ["ai-chat"],
            leftActivePanelID: "connections",
            rightActivePanelID: nil
        ),
    ]
}
