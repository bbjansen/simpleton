// Sources/Simpleton/AppPaths.swift
import Foundation

enum AppPaths {
    static let appSupport: URL = {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Unable to locate Application Support directory")
        }
        return dir.appendingPathComponent("Simpleton")
    }()
}
