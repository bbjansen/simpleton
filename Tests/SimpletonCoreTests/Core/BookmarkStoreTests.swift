// Tests/SimpletonCoreTests/Core/BookmarkStoreTests.swift
import XCTest

@testable import SimpletonCore

final class BookmarkStoreTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testAddAndRetrieveBookmark() async throws {
        let store = BookmarkStore(directory: tempDir)
        let bookmark = Bookmark(name: "test", host: "10.0.1.1")
        try await store.add(bookmark)

        let all = await store.allBookmarks()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].name, "test")
    }

    func testUpdateBookmark() async throws {
        let store = BookmarkStore(directory: tempDir)
        var bookmark = Bookmark(name: "test", host: "10.0.1.1")
        try await store.add(bookmark)

        bookmark.name = "updated"
        try await store.update(bookmark)

        let all = await store.allBookmarks()
        XCTAssertEqual(all[0].name, "updated")
    }

    func testDeleteBookmark() async throws {
        let store = BookmarkStore(directory: tempDir)
        let bookmark = Bookmark(name: "test", host: "10.0.1.1")
        try await store.add(bookmark)
        try await store.delete(id: bookmark.id)

        let all = await store.allBookmarks()
        XCTAssertTrue(all.isEmpty)
    }

    func testPinnedBookmarks() async throws {
        let store = BookmarkStore(directory: tempDir)
        try await store.add(Bookmark(name: "a", host: "1.1.1.1", pinned: false))
        try await store.add(Bookmark(name: "b", host: "2.2.2.2", pinned: true))
        try await store.add(Bookmark(name: "c", host: "3.3.3.3", pinned: true))

        let pinned = await store.pinnedBookmarks()
        XCTAssertEqual(pinned.count, 2)
        XCTAssertTrue(pinned.allSatisfy(\.pinned))
    }

    func testRecordUseUpdatesFrecency() async throws {
        let store = BookmarkStore(directory: tempDir)
        let bookmark = Bookmark(name: "test", host: "10.0.1.1")
        try await store.add(bookmark)
        await store.recordUse(bookmarkId: bookmark.id)

        let entry = await store.frecencyEntry(for: bookmark.id)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.useCount, 1)
        XCTAssertGreaterThan(entry?.score ?? 0, 0)
    }

    func testSearchByFrecency() async throws {
        let store = BookmarkStore(directory: tempDir)
        let b1 = Bookmark(name: "web-prod", host: "10.0.1.1")
        let b2 = Bookmark(name: "web-staging", host: "10.0.2.1")
        try await store.add(b1)
        try await store.add(b2)

        // Use b2 more
        await store.recordUse(bookmarkId: b2.id)
        await store.recordUse(bookmarkId: b2.id)
        await store.recordUse(bookmarkId: b1.id)

        let results = await store.search(query: "web")
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].id, b2.id)  // b2 has higher frecency
    }

    func testPersistenceAcrossInstances() async throws {
        let store1 = BookmarkStore(directory: tempDir)
        try await store1.add(Bookmark(name: "test", host: "10.0.1.1"))
        try await store1.flush()

        let store2 = BookmarkStore(directory: tempDir)
        try await store2.load()
        let all = await store2.allBookmarks()
        XCTAssertEqual(all.count, 1)
    }
}
