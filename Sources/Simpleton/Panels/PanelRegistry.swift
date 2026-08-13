// Sources/Simpleton/Panels/PanelRegistry.swift
import AppKit
import Combine
import SimpletonCore

@MainActor
final class PanelRegistry: ObservableObject {
    @Published private(set) var definitions: [PanelDefinition] = []
    @Published var activeProfile: PanelProfile
    @Published private(set) var profiles: [PanelProfile]

    private let profilesDir: URL

    init(profilesDir: URL) {
        self.profilesDir = profilesDir
        self.profiles = PanelProfile.defaultProfiles
        self.activeProfile = PanelProfile.defaultProfiles[0]
    }

    // MARK: - Registration

    func register(_ panel: PanelDefinition) {
        guard !definitions.contains(where: { $0.id == panel.id }) else { return }
        definitions.append(panel)
    }

    // MARK: - Profile Management

    func loadProfiles() {
        try? FileManager.default.createDirectory(at: profilesDir, withIntermediateDirectories: true)
        let file = profilesDir.appendingPathComponent("profiles.json")
        guard let data = try? Data(contentsOf: file),
            let saved = try? JSONDecoder().decode([PanelProfile].self, from: data)
        else { return }
        // Merge: keep default profiles + append user-created ones (skip if id matches a default)
        let userOnly = saved.filter { p in
            !PanelProfile.defaultProfiles.contains(where: { $0.id == p.id })
        }
        profiles = PanelProfile.defaultProfiles + userOnly
    }

    func saveProfile(_ profile: PanelProfile) throws {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }
        try persistUserProfiles()
        if activeProfile.id == profile.id { activeProfile = profile }
    }

    func deleteProfile(id: UUID) throws {
        guard !PanelProfile.defaultProfiles.contains(where: { $0.id == id }) else { return }
        profiles.removeAll { $0.id == id }
        try persistUserProfiles()
    }

    /// Activate a profile. Controllers are retained so panels preserve their state across switches.
    func activateProfile(_ profile: PanelProfile) {
        activeProfile = profile
        // Let the active workspace re-sync its profile choice if auto-sync is on (AppDelegate decides;
        // it ignores this while it is itself applying a workspace).
        NotificationCenter.default.post(name: .simpletonWorkspaceSetupChanged, object: nil)
    }

    // MARK: - Private

    private func persistUserProfiles() throws {
        let userProfiles = profiles.filter { p in
            !PanelProfile.defaultProfiles.contains(where: { $0.id == p.id })
        }
        try AtomicFileWriter.writeJSON(userProfiles, to: profilesDir.appendingPathComponent("profiles.json"))
    }
}
