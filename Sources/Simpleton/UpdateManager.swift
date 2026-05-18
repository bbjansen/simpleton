// Sources/Simpleton/UpdateManager.swift
import Foundation
import Sparkle
import SimpletonCore

final class UpdateManager {
    private let updaterController: SPUStandardUpdaterController
    private let delegate = UpdateManagerDelegate()

    init(checkMode: UpdateCheckMode) {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: checkMode != .disabled,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
        updaterController.updater.automaticallyChecksForUpdates = (checkMode == .automatic)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func setCheckMode(_ mode: UpdateCheckMode) {
        updaterController.updater.automaticallyChecksForUpdates = (mode == .automatic)
    }
}

private class UpdateManagerDelegate: NSObject, SPUUpdaterDelegate {
    // Placeholder appcast URL — replace with real URL when hosting is set up
    func feedURLString(for updater: SPUUpdater) -> String? {
        "https://simpleton.app/appcast.xml"
    }
}
