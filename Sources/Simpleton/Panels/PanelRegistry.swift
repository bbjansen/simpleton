// Sources/Simpleton/Panels/PanelRegistry.swift
import AppKit
import Combine
import SimpletonCore

@MainActor
final class PanelRegistry: ObservableObject {
    @Published private(set) var definitions: [any PanelDefinition] = []
    @Published var activeProfile: PanelProfile
    @Published private(set) var profiles: [PanelProfile]

    // Cached NSViewControllers keyed by panel id — created lazily, evicted on profile activation
    private var controllers: [String: NSViewController] = [:]
    private let profilesDir: URL

    init(profilesDir: URL) {
        self.profilesDir = profilesDir
        self.profiles = PanelProfile.defaultProfiles
        self.activeProfile = PanelProfile.defaultProfiles[0]
    }

    // MARK: - Registration

    func register(_ panel: any PanelDefinition) {
        guard !definitions.contains(where: { $0.id == panel.id }) else { return }
        definitions.append(panel)
    }

    // MARK: - Controller Cache

    /// Returns a cached controller if one exists, otherwise creates and caches a new one.
    func makeController(for id: String, context: PanelContext) -> NSViewController? {
        if let cached = controllers[id] { return cached }
        guard let def = definitions.first(where: { $0.id == id }) else { return nil }
        let vc = def.makeViewController(context: context)
        controllers[id] = vc
        return vc
    }

    func evictController(for id: String) {
        controllers.removeValue(forKey: id)
    }

    // MARK: - Profile Management

    func loadProfiles() {
        try? FileManager.default.createDirectory(at: profilesDir, withIntermediateDirectories: true)
        let file = profilesDir.appendingPathComponent("profiles.json")
        guard let data = try? Data(contentsOf: file),
              let saved = try? JSONDecoder().decode([PanelProfile].self, from: data) else { return }
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

    /// Activate a profile, evicting all cached controllers so panels rebuild with a fresh context.
    func activateProfile(_ profile: PanelProfile) {
        controllers.removeAll()
        activeProfile = profile
    }

    // MARK: - Private

    private func persistUserProfiles() throws {
        let userProfiles = profiles.filter { p in
            !PanelProfile.defaultProfiles.contains(where: { $0.id == p.id })
        }
        try AtomicFileWriter.writeJSON(userProfiles, to: profilesDir.appendingPathComponent("profiles.json"))
    }
}
