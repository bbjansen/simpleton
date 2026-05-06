// Sources/Simpleton/SessionManager.swift
import AppKit
import SimpletonCore

/// Manages session state persistence — periodic saves, crash recovery, and restore.
final class SessionManager {

    private let directory: URL
    private let filename = "session-state.json"
    private var saveTimer: Timer?
    private var stateProvider: (() -> SessionState)?

    init(directory: URL) {
        self.directory = directory
    }

    deinit {
        saveTimer?.invalidate()
    }

    /// Set the state provider — called to get the current session state for saving.
    func setStateProvider(_ provider: @escaping () -> SessionState) {
        self.stateProvider = provider
    }

    /// Start periodic saving (every 30 seconds).
    func startPeriodicSave() {
        // Mark as not cleanly shut down
        markDirty()

        saveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.saveCurrentState()
        }
    }

    /// Stop periodic saving and mark clean shutdown.
    func stopAndMarkClean() {
        saveTimer?.invalidate()
        saveTimer = nil
        markClean()
    }

    /// Save the current state immediately (called on split/tab changes).
    func saveCurrentState() {
        guard var state = stateProvider?() else { return }
        state.cleanShutdown = false
        state.savedAt = Date()
        let file = SessionStateFile(state: state)
        try? AtomicFileWriter.writeJSON(file, to: stateFileURL)
    }

    /// Check if the last session crashed (cleanShutdown == false).
    func didCrashLastSession() -> Bool {
        guard let file = loadStateFile() else { return false }
        return !file.state.cleanShutdown
    }

    /// Load the saved session state (for restore).
    func loadSavedState() -> SessionState? {
        return loadStateFile()?.state
    }

    /// Delete saved state (after successful restore or user dismisses).
    func clearSavedState() {
        try? FileManager.default.removeItem(at: stateFileURL)
    }

    // MARK: - Private

    private var stateFileURL: URL {
        directory.appendingPathComponent(filename)
    }

    private func loadStateFile() -> SessionStateFile? {
        guard FileManager.default.fileExists(atPath: stateFileURL.path) else { return nil }
        return try? AtomicFileWriter.readJSON(SessionStateFile.self, from: stateFileURL)
    }

    private func markDirty() {
        // Write a minimal state with cleanShutdown = false
        if var file = loadStateFile() {
            file.state.cleanShutdown = false
            try? AtomicFileWriter.writeJSON(SessionStateFile(state: file.state), to: stateFileURL)
        } else {
            let state = SessionState(cleanShutdown: false, savedAt: Date(), windows: [])
            try? AtomicFileWriter.writeJSON(SessionStateFile(state: state), to: stateFileURL)
        }
    }

    private func markClean() {
        guard var file = loadStateFile() else { return }
        file.state.cleanShutdown = true
        try? AtomicFileWriter.writeJSON(SessionStateFile(state: file.state), to: stateFileURL)
    }
}
