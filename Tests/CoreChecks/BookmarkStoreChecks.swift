// Tests/CoreChecks/BookmarkStoreChecks.swift
// Ported from Tests/SimpletonCoreTests/Core/BookmarkStoreTests.swift
import Foundation
import SimpletonCore

func runBookmarkStoreChecks(_ t: TestRunner) async {
    func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("corechecks-" + UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    await t.suite("BookmarkStore.testAddAndRetrieveBookmark") {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        do {
            let store = BookmarkStore(directory: tempDir)
            let bookmark = Bookmark(name: "test", host: "10.0.1.1")
            try await store.add(bookmark)
            let all = await store.allBookmarks()
            t.expectEqual(all.count, 1, "one bookmark stored")
            t.expectEqual(all.first?.name, "test", "bookmark name")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    await t.suite("BookmarkStore.testUpdateBookmark") {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        do {
            let store = BookmarkStore(directory: tempDir)
            var bookmark = Bookmark(name: "test", host: "10.0.1.1")
            try await store.add(bookmark)
            bookmark.name = "updated"
            try await store.update(bookmark)
            let all = await store.allBookmarks()
            t.expectEqual(all.first?.name, "updated", "bookmark renamed")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    await t.suite("BookmarkStore.testDeleteBookmark") {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        do {
            let store = BookmarkStore(directory: tempDir)
            let bookmark = Bookmark(name: "test", host: "10.0.1.1")
            try await store.add(bookmark)
            try await store.delete(id: bookmark.id)
            let all = await store.allBookmarks()
            t.expect(all.isEmpty, "store empty after delete")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    await t.suite("BookmarkStore.testPinnedBookmarks") {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        do {
            let store = BookmarkStore(directory: tempDir)
            try await store.add(Bookmark(name: "a", host: "1.1.1.1", pinned: false))
            try await store.add(Bookmark(name: "b", host: "2.2.2.2", pinned: true))
            try await store.add(Bookmark(name: "c", host: "3.3.3.3", pinned: true))
            let pinned = await store.pinnedBookmarks()
            t.expectEqual(pinned.count, 2, "two pinned bookmarks")
            t.expect(pinned.allSatisfy(\.pinned), "all returned are pinned")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    await t.suite("BookmarkStore.testRecordUseUpdatesFrecency") {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        do {
            let store = BookmarkStore(directory: tempDir)
            let bookmark = Bookmark(name: "test", host: "10.0.1.1")
            try await store.add(bookmark)
            await store.recordUse(bookmarkId: bookmark.id)
            let entry = await store.frecencyEntry(for: bookmark.id)
            t.expect(entry != nil, "frecency entry exists")
            t.expectEqual(entry?.useCount, 1, "useCount is 1")
            t.expect((entry?.score ?? 0) > 0, "score > 0")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    await t.suite("BookmarkStore.testSearchByFrecency") {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        do {
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
            t.expectEqual(results.count, 2, "both bookmarks matched")
            t.expectEqual(results.first?.id, b2.id, "b2 has higher frecency, ranks first")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    await t.suite("BookmarkStore.testPersistenceAcrossInstances") {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        do {
            let store1 = BookmarkStore(directory: tempDir)
            try await store1.add(Bookmark(name: "test", host: "10.0.1.1"))
            try await store1.flush()

            let store2 = BookmarkStore(directory: tempDir)
            try await store2.load()
            let all = await store2.allBookmarks()
            t.expectEqual(all.count, 1, "second instance loads persisted bookmark")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }
}
