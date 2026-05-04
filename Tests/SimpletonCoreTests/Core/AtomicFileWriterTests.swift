// Tests/SimpletonCoreTests/Core/AtomicFileWriterTests.swift
import XCTest
@testable import SimpletonCore

final class AtomicFileWriterTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testWriteAndRead() throws {
        let file = tempDir.appendingPathComponent("test.json")
        let data = Data("{\"key\":\"value\"}".utf8)

        try AtomicFileWriter.write(data: data, to: file)
        let read = try Data(contentsOf: file)
        XCTAssertEqual(read, data)
    }

    func testOverwriteExisting() throws {
        let file = tempDir.appendingPathComponent("test.json")
        try AtomicFileWriter.write(data: Data("first".utf8), to: file)
        try AtomicFileWriter.write(data: Data("second".utf8), to: file)
        let read = String(data: try Data(contentsOf: file), encoding: .utf8)
        XCTAssertEqual(read, "second")
    }

    func testNoOrphanedTempFiles() throws {
        let file = tempDir.appendingPathComponent("test.json")
        try AtomicFileWriter.write(data: Data("data".utf8), to: file)
        let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        XCTAssertEqual(contents.count, 1)
        XCTAssertEqual(contents[0].lastPathComponent, "test.json")
    }

    func testWriteEncodable() throws {
        let file = tempDir.appendingPathComponent("config.json")
        let config = ConfigFile()
        try AtomicFileWriter.writeJSON(config, to: file)

        let data = try Data(contentsOf: file)
        let decoded = try JSONDecoder().decode(ConfigFile.self, from: data)
        XCTAssertEqual(decoded.version, 1)
    }
}
