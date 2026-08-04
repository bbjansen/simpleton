// Sources/SimpletonCore/Core/BookmarkStore.swift
import Foundation

public extension Notification.Name {
    /// Posted on the main queue after bookmarks or their frecency change, so UI can refresh.
    static let simpletonBookmarksChanged = Notification.Name("simpletonBookmarksChanged")
}

public actor BookmarkStore {

    private let directory: URL
    private var bookmarks: [UUID: Bookmark] = [:]
    private var frecency: [UUID: FrecencyEntry] = [:]
    private var loaded = false

    public init(directory: URL) {
        self.directory = directory
    }

    nonisolated private func postBookmarksChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .simpletonBookmarksChanged, object: nil)
        }
    }

    public func load() throws {
        let bookmarkFile = directory.appendingPathComponent("bookmarks.json")
        if FileManager.default.fileExists(atPath: bookmarkFile.path) {
            let file = try AtomicFileWriter.readJSON(BookmarkFile.self, from: bookmarkFile)
            bookmarks = Dictionary(uniqueKeysWithValues: file.bookmarks.map { ($0.id, $0) })
        }

        let frecencyFile = directory.appendingPathComponent("frecency.json")
        if FileManager.default.fileExists(atPath: frecencyFile.path) {
            let file = try AtomicFileWriter.readJSON(FrecencyFile.self, from: frecencyFile)
            frecency = file.entries
        }

        loaded = true
    }

    private func ensureLoaded() throws {
        if !loaded { try load() }
    }

    public func add(_ bookmark: Bookmark) throws {
        try ensureLoaded()
        bookmarks[bookmark.id] = bookmark
        try saveBookmarks()
        postBookmarksChanged()
    }

    public func update(_ bookmark: Bookmark) throws {
        try ensureLoaded()
        guard bookmarks[bookmark.id] != nil else { return }
        var updated = bookmark
        updated.updatedAt = Date()
        bookmarks[bookmark.id] = updated
        try saveBookmarks()
        postBookmarksChanged()
    }

    public func delete(id: UUID) throws {
        try ensureLoaded()
        bookmarks.removeValue(forKey: id)
        frecency.removeValue(forKey: id)
        try saveBookmarks()
        try saveFrecency()
        postBookmarksChanged()
    }

    public func allBookmarks() -> [Bookmark] {
        try? ensureLoaded()
        return Array(bookmarks.values).sorted { $0.name < $1.name }
    }

    public func pinnedBookmarks() -> [Bookmark] {
        try? ensureLoaded()
        return bookmarks.values.filter(\.pinned).sorted { $0.name < $1.name }
    }

    public func bookmark(for id: UUID) -> Bookmark? {
        try? ensureLoaded()
        return bookmarks[id]
    }

    public func recordUse(bookmarkId: UUID) {
        let entry = frecency[bookmarkId] ?? FrecencyEntry()
        frecency[bookmarkId] = FrecencyScorer.recordUse(entry: entry)
        try? saveFrecency()
        postBookmarksChanged()
    }

    public func frecencyEntry(for id: UUID) -> FrecencyEntry? {
        frecency[id]
    }

    public func search(query: String) -> [Bookmark] {
        try? ensureLoaded()
        let scored = bookmarks.values.compactMap { bookmark -> (Bookmark, Double)? in
            // Match against name and host
            let nameScore = FuzzyMatcher.score(query: query, candidate: bookmark.name)
            let hostScore = FuzzyMatcher.score(query: query, candidate: bookmark.host)
            guard let matchScore = [nameScore, hostScore].compactMap({ $0 }).max() else { return nil }

            let frecencyScore = frecency[bookmark.id]?.score ?? 0
            let combined = matchScore + frecencyScore
            return (bookmark, combined)
        }
        return scored.sorted { $0.1 > $1.1 }.map(\.0)
    }

    public func flush() throws {
        try saveBookmarks()
        try saveFrecency()
    }

    private func saveBookmarks() throws {
        let file = BookmarkFile(bookmarks: Array(bookmarks.values))
        try AtomicFileWriter.writeJSON(file, to: directory.appendingPathComponent("bookmarks.json"))
    }

    private func saveFrecency() throws {
        let file = FrecencyFile(entries: frecency)
        try AtomicFileWriter.writeJSON(file, to: directory.appendingPathComponent("frecency.json"))
    }
}
