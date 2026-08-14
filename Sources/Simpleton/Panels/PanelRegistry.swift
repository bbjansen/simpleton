// Sources/Simpleton/Panels/PanelRegistry.swift
import AppKit
import Combine
import SimpletonCore

/// On-disk shape of `profiles.json`: every profile (including edited built-ins) plus the id of the
/// active one. Written on activate and on every runtime edit, so the selected profile and all
/// layout/width/drawer tweaks survive a relaunch (mirroring how config.json persists the theme).
struct ProfilesStore: Codable {
    var profiles: [PanelProfile]
    var activeProfileID: String?

    /// Tolerant decode so a store written by an older build (or with fields added later) still loads.
    init(profiles: [PanelProfile], activeProfileID: String?) {
        self.profiles = profiles
        self.activeProfileID = activeProfileID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profiles = try c.decodeIfPresent([PanelProfile].self, forKey: .profiles) ?? []
        activeProfileID = try c.decodeIfPresent(String.self, forKey: .activeProfileID)
    }
}

@MainActor
final class PanelRegistry: ObservableObject {
    @Published private(set) var definitions: [PanelDefinition] = []
    @Published var activeProfile: PanelProfile
    @Published private(set) var profiles: [PanelProfile]

    private let profilesDir: URL

    private var profilesFile: URL { profilesDir.appendingPathComponent("profiles.json") }

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

    /// Read `profiles.json` and reconstruct the full profile set + active selection.
    ///
    /// Backward compatible: prefers the new `ProfilesStore` wrapper, falling back to a legacy bare
    /// `[PanelProfile]` (which older builds wrote — user-created profiles only). Profiles are merged
    /// **by id** against the code defaults so that: edited built-ins restore their overrides, brand-new
    /// code defaults appear automatically, and user-created profiles always survive.
    func loadProfiles() {
        try? FileManager.default.createDirectory(at: profilesDir, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: profilesFile) else { return }

        let decoder = JSONDecoder()
        let savedProfiles: [PanelProfile]
        let savedActiveID: String?
        if let store = try? decoder.decode(ProfilesStore.self, from: data) {
            savedProfiles = store.profiles
            savedActiveID = store.activeProfileID
        } else if let legacy = try? decoder.decode([PanelProfile].self, from: data) {
            // Legacy format: a bare array of the user's non-default profiles. No active id recorded.
            savedProfiles = legacy
            savedActiveID = nil
        } else {
            return  // Unreadable — keep the code defaults rather than losing the file's semantics.
        }

        let savedByID = Dictionary(savedProfiles.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let defaultIDs = Set(PanelProfile.defaultProfiles.map(\.id))
        // Built-ins: use the saved (edited) version when present, else the fresh code default.
        let merged = PanelProfile.defaultProfiles.map { savedByID[$0.id] ?? $0 }
        // User profiles: everything saved that isn't a built-in, in their saved order.
        let userProfiles = savedProfiles.filter { !defaultIDs.contains($0.id) }
        profiles = merged + userProfiles

        // Restore the active selection, falling back to the first profile.
        if let activeID = savedActiveID, let uuid = UUID(uuidString: activeID),
            let match = profiles.first(where: { $0.id == uuid })
        {
            activeProfile = match
        } else {
            activeProfile = profiles.first ?? PanelProfile.defaultProfiles[0]
        }
    }

    func saveProfile(_ profile: PanelProfile) throws {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }
        if activeProfile.id == profile.id { activeProfile = profile }
        try persist()
    }

    func deleteProfile(id: UUID) throws {
        guard !PanelProfile.defaultProfiles.contains(where: { $0.id == id }) else { return }
        profiles.removeAll { $0.id == id }
        // If the deleted profile was active, fall back to the first remaining profile.
        if activeProfile.id == id { activeProfile = profiles.first ?? PanelProfile.defaultProfiles[0] }
        try persist()
    }

    /// Replace a built-in profile with its pristine code default (the "Reset to Default" action) and
    /// persist. No-op for non-built-in ids. If the profile is active, the reset version becomes active.
    func resetProfileToDefault(id: UUID) throws {
        guard let codeDefault = PanelProfile.defaultProfiles.first(where: { $0.id == id }) else { return }
        if let idx = profiles.firstIndex(where: { $0.id == id }) {
            profiles[idx] = codeDefault
        } else {
            profiles.append(codeDefault)
        }
        if activeProfile.id == id { activeProfile = codeDefault }
        try persist()
    }

    /// Activate a profile. Controllers are retained so panels preserve their state across switches.
    /// Persists the selection so the chosen profile is restored on the next launch.
    func activateProfile(_ profile: PanelProfile) {
        activeProfile = profile
        try? persist()
        // Let the active workspace re-sync its profile choice if auto-sync is on (AppDelegate decides;
        // it ignores this while it is itself applying a workspace).
        NotificationCenter.default.post(name: .simpletonWorkspaceSetupChanged, object: nil)
    }

    /// The single funnel for runtime edits to the active profile (add/remove/active-panel, drawer,
    /// widths). Mutates the active profile in place, keeps `profiles` in sync, and persists — so any
    /// change made by dragging a panel, opening the drawer, or resizing a divider sticks across launches.
    func updateActiveProfile(_ transform: (inout PanelProfile) -> Void) {
        var profile = activeProfile
        transform(&profile)
        guard profile != activeProfile else { return }
        activeProfile = profile
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }
        try? persist()
    }

    // MARK: - Private

    /// Persist the whole store (all profiles + the active id) atomically.
    private func persist() throws {
        let store = ProfilesStore(profiles: profiles, activeProfileID: activeProfile.id.uuidString)
        try AtomicFileWriter.writeJSON(store, to: profilesFile)
    }
}
