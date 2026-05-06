// Sources/Simpleton/WorkspaceManager.swift
import Foundation
import SimpletonCore

/// Manages named workspaces — save, load, list, lock.
final class WorkspaceManager {

    private let directory: URL
    /// Maps workspace name -> window ID currently using it (for locking).
    private var lockedWorkspaces: [String: UUID] = [:]

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// List all saved workspace names.
    func listWorkspaces() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> String? in
                guard let file = try? AtomicFileWriter.readJSON(WorkspaceFile.self, from: url) else { return nil }
                return file.workspace.name
            }
            .sorted()
    }

    /// Save a workspace. Overwrites if name already exists.
    func save(workspace: Workspace) throws {
        let filename = sanitizeFilename(workspace.name) + ".json"
        let url = directory.appendingPathComponent(filename)
        let file = WorkspaceFile(workspace: workspace)
        try AtomicFileWriter.writeJSON(file, to: url)
    }

    /// Load a workspace by name. Returns nil if not found.
    func load(name: String) -> Workspace? {
        let filename = sanitizeFilename(name) + ".json"
        let url = directory.appendingPathComponent(filename)
        guard let file = try? AtomicFileWriter.readJSON(WorkspaceFile.self, from: url) else { return nil }
        return file.workspace
    }

    /// Delete a workspace by name.
    func delete(name: String) {
        let filename = sanitizeFilename(name) + ".json"
        let url = directory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
        lockedWorkspaces.removeValue(forKey: name)
    }

    /// Lock a workspace to a window. Returns false if already locked by another window.
    func lock(name: String, windowID: UUID) -> Bool {
        if let existing = lockedWorkspaces[name], existing != windowID {
            return false // Already locked by different window
        }
        lockedWorkspaces[name] = windowID
        return true
    }

    /// Unlock a workspace (when window closes).
    func unlock(name: String) {
        lockedWorkspaces.removeValue(forKey: name)
    }

    /// Check if a workspace is currently locked.
    func isLocked(name: String) -> Bool {
        lockedWorkspaces[name] != nil
    }

    /// Get the window ID that has a workspace locked.
    func lockedBy(name: String) -> UUID? {
        lockedWorkspaces[name]
    }

    // MARK: - Helpers

    private func sanitizeFilename(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return name
            .components(separatedBy: allowed.inverted)
            .joined(separator: "-")
            .lowercased()
    }
}
