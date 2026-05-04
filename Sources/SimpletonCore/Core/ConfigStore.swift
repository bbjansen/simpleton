// Sources/SimpletonCore/Core/ConfigStore.swift
import Foundation

public actor ConfigStore {

    private let directory: URL
    private let filename = "config.json"
    private var cached: AppConfig?

    public init(directory: URL) {
        self.directory = directory
    }

    public func load() throws -> AppConfig {
        if let cached { return cached }

        let file = directory.appendingPathComponent(filename)
        let tmpFile = directory.appendingPathComponent(".\(filename).tmp")

        // Check for orphaned temp file (crash recovery)
        if FileManager.default.fileExists(atPath: tmpFile.path) {
            if let recovered = try? AtomicFileWriter.readJSON(ConfigFile.self, from: tmpFile) {
                cached = recovered.config
                // Clean up: write proper file, remove tmp
                try? AtomicFileWriter.writeJSON(ConfigFile(config: recovered.config), to: file)
                try? FileManager.default.removeItem(at: tmpFile)
                return recovered.config
            }
            try? FileManager.default.removeItem(at: tmpFile)
        }

        guard FileManager.default.fileExists(atPath: file.path) else {
            let defaultConfig = AppConfig()
            cached = defaultConfig
            try AtomicFileWriter.writeJSON(ConfigFile(config: defaultConfig), to: file)
            return defaultConfig
        }

        do {
            let configFile = try AtomicFileWriter.readJSON(ConfigFile.self, from: file)
            cached = configFile.config
            return configFile.config
        } catch {
            // Corrupted file — fall back to defaults
            let defaultConfig = AppConfig()
            cached = defaultConfig
            return defaultConfig
        }
    }

    public func save(_ config: AppConfig) throws {
        let file = directory.appendingPathComponent(filename)
        try AtomicFileWriter.writeJSON(ConfigFile(config: config), to: file)
        cached = config
    }
}
