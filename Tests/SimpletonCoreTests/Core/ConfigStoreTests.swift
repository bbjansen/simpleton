// Tests/SimpletonCoreTests/Core/ConfigStoreTests.swift
import XCTest

@testable import SimpletonCore

final class ConfigStoreTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testLoadCreatesDefaultConfig() async throws {
        let store = ConfigStore(directory: tempDir)
        let config = try await store.load()
        XCTAssertEqual(config.appearance.fontFamily, "SF Mono")
        XCTAssertEqual(config.terminal.scrollbackLines, 10000)
    }

    func testSaveAndReload() async throws {
        let store = ConfigStore(directory: tempDir)
        var config = try await store.load()
        config.appearance.fontSize = 18
        try await store.save(config)

        let store2 = ConfigStore(directory: tempDir)
        let reloaded = try await store2.load()
        XCTAssertEqual(reloaded.appearance.fontSize, 18)
    }

    func testCorruptedConfigFallsBackToDefault() async throws {
        let file = tempDir.appendingPathComponent("config.json")
        try "this is not json".write(to: file, atomically: true, encoding: .utf8)

        let store = ConfigStore(directory: tempDir)
        let config = try await store.load()
        XCTAssertEqual(config.appearance.fontFamily, "SF Mono")  // default
    }

    func testOrphanedTempFileRecovery() async throws {
        // Write valid config to .tmp file (simulating crash mid-write)
        var config = AppConfig()
        config.appearance.fontSize = 20
        let tmpFile = tempDir.appendingPathComponent(".config.json.tmp")
        try AtomicFileWriter.writeJSON(ConfigFile(config: config), to: tmpFile)

        let store = ConfigStore(directory: tempDir)
        let loaded = try await store.load()
        XCTAssertEqual(loaded.appearance.fontSize, 20)
    }
}
