// Sources/Simpleton/AppTranslocationCheck.swift
import AppKit

enum AppTranslocationCheck {

    /// Returns true if the app appears to be running from a translocated path.
    /// Gatekeeper translocates apps launched from Downloads or quarantined locations.
    static func isTranslocated() -> Bool {
        let bundlePath = Bundle.main.bundlePath
        // Translocated apps run from /private/var/folders/.../AppTranslocation/...
        return bundlePath.contains("AppTranslocation") || bundlePath.contains("/private/var/folders/")
    }

    /// Show a warning dialog if translocated.
    static func checkAndWarn() {
        // Only relevant when running as a .app bundle
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }
        guard isTranslocated() else { return }

        let alert = NSAlert()
        alert.messageText = "Move Simpleton to Applications"
        alert.informativeText =
            "Simpleton is running from a temporary location (Downloads or quarantined path). Move it to /Applications for proper operation and automatic updates."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Finder")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open Finder showing the app's current location
            NSWorkspace.shared.selectFile(Bundle.main.bundlePath, inFileViewerRootedAtPath: "")
        }
    }
}
