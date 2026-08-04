// Sources/Simpleton/AppPaths.swift
import Foundation

enum AppPaths {
    static let appSupport: URL = {
        // Allow overriding the support directory via SIMPLETON_SUPPORT_DIR. Useful for tests,
        // demo/screenshot captures, and portable runs so they never touch the real config.
        if let override = ProcessInfo.processInfo.environment["SIMPLETON_SUPPORT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Unable to locate Application Support directory")
        }
        return dir.appendingPathComponent("Simpleton")
    }()
}
