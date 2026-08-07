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
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else {
            return []
        }
        return
            files
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

    /// Rename a workspace: load it, save it under the new name (carrying the full setup + layout), and
    /// delete the old file. No-op if the source doesn't exist or the names are equal. Returns success.
    @discardableResult
    func rename(from oldName: String, to newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != oldName, var ws = load(name: oldName) else { return false }
        ws.name = trimmed
        do {
            try save(workspace: ws)
        } catch {
            return false
        }
        // Only remove the old file if the new name maps to a different file — otherwise the sanitized
        // filenames collide (e.g. "My WS" vs "my-ws") and deleting would remove what we just wrote.
        if sanitizeFilename(oldName) != sanitizeFilename(trimmed) {
            delete(name: oldName)
        }
        return true
    }

    /// Duplicate a workspace under "<name> copy" (carrying its full setup + layout). Returns the new
    /// name, or nil if the source doesn't exist.
    @discardableResult
    func duplicate(name: String) -> String? {
        guard var ws = load(name: name) else { return nil }
        let copyName = "\(name) copy"
        ws.name = copyName
        ws.savedAt = Date()
        do {
            try save(workspace: ws)
        } catch {
            return nil
        }
        return copyName
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
            return false  // Already locked by different window
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
        return
            name
            .components(separatedBy: allowed.inverted)
            .joined(separator: "-")
            .lowercased()
    }
}
