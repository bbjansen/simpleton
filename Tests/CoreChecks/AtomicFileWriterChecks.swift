// Tests/CoreChecks/AtomicFileWriterChecks.swift
// Ported from Tests/SimpletonCoreTests/Core/AtomicFileWriterTests.swift
import Foundation
import SimpletonCore

func runAtomicFileWriterChecks(_ t: TestRunner) {
    t.suite("AtomicFileWriter.testWriteAndRead") {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("corechecks-" + UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        do {
            let file = tempDir.appendingPathComponent("test.json")
            let data = Data("{\"key\":\"value\"}".utf8)
            try AtomicFileWriter.write(data: data, to: file)
            let read = try Data(contentsOf: file)
            t.expectEqual(read, data, "read back equals written data")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    t.suite("AtomicFileWriter.testOverwriteExisting") {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("corechecks-" + UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        do {
            let file = tempDir.appendingPathComponent("test.json")
            try AtomicFileWriter.write(data: Data("first".utf8), to: file)
            try AtomicFileWriter.write(data: Data("second".utf8), to: file)
            let read = String(data: try Data(contentsOf: file), encoding: .utf8)
            t.expectEqual(read, "second", "second write overwrites first")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    t.suite("AtomicFileWriter.testNoOrphanedTempFiles") {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("corechecks-" + UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        do {
            let file = tempDir.appendingPathComponent("test.json")
            try AtomicFileWriter.write(data: Data("data".utf8), to: file)
            let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            t.expectEqual(contents.count, 1, "only the target file remains")
            t.expectEqual(contents.first?.lastPathComponent, "test.json", "remaining file is the target")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    t.suite("AtomicFileWriter.testWriteEncodable") {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("corechecks-" + UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        do {
            let file = tempDir.appendingPathComponent("config.json")
            let config = ConfigFile()
            try AtomicFileWriter.writeJSON(config, to: file)
            let data = try Data(contentsOf: file)
            let decoded = try JSONDecoder().decode(ConfigFile.self, from: data)
            t.expectEqual(decoded.version, 1, "decoded version")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }
}
