// Sources/SimpletonCore/Stores/SpecWorkspaceStore.swift
import Foundation

/// Persists `SpecWorkspaceState` per project and resolves/reads/writes the repo-local markdown
/// artifacts under `<projectRoot>/.plan/`.
///
/// Two storage concerns, deliberately separate:
///  - **Workspace state** (which mode/artifact was active) is app-private UI state, stored as JSON
///    under the injectable `directory` keyed by a stable hash of the project path — so reopening a
///    project restores its last mode without writing anything into the user's repo.
///  - **Artifacts** (`plan.md`, …) are the user-visible, git-committable product and live in the
///    project's own `.plan/` directory.
///
/// `directory` is injectable (defaulting to a real app-support subdir) so CoreChecks can exercise
/// the full save→load round-trip against a temp directory. Modeled on `SQLSavedQueryStore`.
public actor SpecWorkspaceStore {
    private let fileURL: URL
    private var byProject: [String: SpecWorkspaceState] = [:]
    private var loaded = false

    /// - Parameter directory: base directory for the app-private state file. Defaults to a
    ///   `spec-dev` subdirectory of the user's Application Support/Simpleton directory.
    public init(directory: URL = SpecWorkspaceStore.defaultDirectory) {
        self.fileURL = directory.appendingPathComponent("spec-workspace.json")
    }

    /// Default app-support location, mirroring `AppPaths.appSupport` (honoring the test/portable
    /// `SIMPLETON_SUPPORT_DIR` override) without the app target having to import anything here.
    public static var defaultDirectory: URL {
        let base: URL
        if let override = ProcessInfo.processInfo.environment["SIMPLETON_SUPPORT_DIR"], !override.isEmpty {
            base = URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        } else if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            base = support.appendingPathComponent("Simpleton")
        } else {
            base = FileManager.default.temporaryDirectory.appendingPathComponent("Simpleton")
        }
        return base.appendingPathComponent("spec-dev")
    }

    // MARK: - Workspace state persistence

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        guard let decoded = try? AtomicFileWriter.readJSON(SavedFile.self, from: fileURL) else { return }
        byProject = decoded.byProject
    }

    /// The saved state for a project path, or a fresh default seeded with that path when none exists.
    public func state(for projectPath: String) -> SpecWorkspaceState {
        ensureLoaded()
        return byProject[Self.projectKey(projectPath)]
            ?? SpecWorkspaceState(projectPath: projectPath)
    }

    /// Upsert the state for its `projectPath`, stamping `updatedAt`, and persist atomically.
    public func save(_ state: SpecWorkspaceState) {
        ensureLoaded()
        var stamped = state
        stamped.updatedAt = Date()
        byProject[Self.projectKey(state.projectPath)] = stamped
        try? persist()
    }

    private func persist() throws {
        try AtomicFileWriter.writeJSON(SavedFile(byProject: byProject), to: fileURL)
    }

    /// A stable, filesystem-independent key for a project path. A hash keeps the JSON keys compact
    /// and avoids leaking long absolute paths as dictionary keys while staying deterministic.
    public static func projectKey(_ projectPath: String) -> String {
        let normalized = projectPath.isEmpty ? "global" : projectPath
        return String(format: "%016x", UInt64(bitPattern: Int64(stableHash(normalized))))
    }

    /// Deterministic FNV-1a 64-bit hash (Swift's `Hasher` is per-process seeded, so unusable for a
    /// key that must survive relaunches).
    private static func stableHash(_ string: String) -> Int64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return Int64(bitPattern: hash)
    }

    // MARK: - Artifact (markdown) files under <projectRoot>/.plan/

    /// The `.plan/` directory for a project root.
    public nonisolated static func planDirectory(for projectRoot: String) -> URL {
        URL(fileURLWithPath: projectRoot, isDirectory: true).appendingPathComponent(".plan", isDirectory: true)
    }

    /// The absolute URL of an artifact's markdown file inside `<projectRoot>/.plan/`.
    public nonisolated static func artifactURL(_ artifact: SpecArtifact, projectRoot: String) -> URL {
        planDirectory(for: projectRoot).appendingPathComponent(artifact.fileName)
    }

    /// Read an artifact's markdown. Returns an empty string when the file doesn't exist yet.
    public func readArtifact(_ artifact: SpecArtifact, projectRoot: String) -> String {
        let url = Self.artifactURL(artifact, projectRoot: projectRoot)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// Write an artifact's markdown, creating `<projectRoot>/.plan/` if missing. Writes atomically.
    public func writeArtifact(_ artifact: SpecArtifact, projectRoot: String, contents: String) throws {
        let url = Self.artifactURL(artifact, projectRoot: projectRoot)
        try AtomicFileWriter.write(data: Data(contents.utf8), to: url)
    }

    // MARK: - On-disk shape

    private struct SavedFile: Codable {
        var version: Int = 1
        var byProject: [String: SpecWorkspaceState] = [:]
        init(byProject: [String: SpecWorkspaceState]) { self.byProject = byProject }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
            byProject = try c.decodeIfPresent([String: SpecWorkspaceState].self, forKey: .byProject) ?? [:]
        }
    }
}
