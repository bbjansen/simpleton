// Tests/CoreChecks/ConfigStoreChecks.swift
// Ported from Tests/SimpletonCoreTests/Core/ConfigStoreTests.swift
import Foundation
import SimpletonCore

func runConfigStoreChecks(_ t: TestRunner) async {
    func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("corechecks-" + UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    await t.suite("ConfigStore.testLoadCreatesDefaultConfig") {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        do {
            let store = ConfigStore(directory: tempDir)
            let config = try await store.load()
            t.expectEqual(config.appearance.fontFamily, "SF Mono", "default font family")
            t.expectEqual(config.terminal.scrollbackLines, 10000, "default scrollback")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    await t.suite("ConfigStore.testSaveAndReload") {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        do {
            let store = ConfigStore(directory: tempDir)
            var config = try await store.load()
            config.appearance.fontSize = 18
            try await store.save(config)

            let store2 = ConfigStore(directory: tempDir)
            let reloaded = try await store2.load()
            t.expectEqual(reloaded.appearance.fontSize, 18, "reloaded font size persisted")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    await t.suite("ConfigStore.testCorruptedConfigFallsBackToDefault") {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        do {
            let file = tempDir.appendingPathComponent("config.json")
            try "this is not json".write(to: file, atomically: true, encoding: .utf8)

            let store = ConfigStore(directory: tempDir)
            let config = try await store.load()
            t.expectEqual(config.appearance.fontFamily, "SF Mono", "corrupted config falls back to default")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    await t.suite("ConfigStore.testOrphanedTempFileRecovery") {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        do {
            // Write valid config to .tmp file (simulating crash mid-write)
            var config = AppConfig()
            config.appearance.fontSize = 20
            let tmpFile = tempDir.appendingPathComponent(".config.json.tmp")
            try AtomicFileWriter.writeJSON(ConfigFile(config: config), to: tmpFile)

            let store = ConfigStore(directory: tempDir)
            let loaded = try await store.load()
            t.expectEqual(loaded.appearance.fontSize, 20, "orphaned temp file recovered")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }
}
