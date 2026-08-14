import Foundation
import SimpletonSQL

func runSQLSavedQueryStoreChecks(_ t: TestRunner) async {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("saved-queries-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let conn = UUID()
    let other = UUID()

    await t.suite("SQLSavedQueryStore save + list sorted") {
        let store = SQLSavedQueryStore(directory: dir)
        await store.save(name: "Zebras", sql: "SELECT 1", for: conn)
        await store.save(name: "apples", sql: "SELECT 2", for: conn)
        let list = await store.saved(for: conn)
        t.expectEqual(list.map(\.name), ["apples", "Zebras"], "sorted case-insensitively")
        t.expectEqual(list.first?.sql, "SELECT 2", "sql preserved")
    }

    await t.suite("SQLSavedQueryStore upsert by name") {
        let store = SQLSavedQueryStore(directory: dir)
        await store.save(name: "apples", sql: "SELECT 99", for: conn)
        let list = await store.saved(for: conn)
        t.expectEqual(list.filter { $0.name == "apples" }.count, 1, "no duplicate name")
        t.expectEqual(list.first { $0.name == "apples" }?.sql, "SELECT 99", "sql overwritten")
    }

    await t.suite("SQLSavedQueryStore ignores blank name / sql") {
        let store = SQLSavedQueryStore(directory: dir)
        await store.save(name: "   ", sql: "SELECT 1", for: conn)
        await store.save(name: "ok", sql: "   ", for: conn)
        let names = await store.saved(for: conn).map(\.name)
        t.expect(!names.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }), "no blank name")
        t.expect(!names.contains("ok"), "blank sql not saved")
    }

    await t.suite("SQLSavedQueryStore remove + per-connection isolation") {
        let store = SQLSavedQueryStore(directory: dir)
        await store.save(name: "shared", sql: "SELECT 3", for: other)
        await store.remove(name: "Zebras", for: conn)
        let connNames = await store.saved(for: conn).map(\.name)
        t.expect(!connNames.contains("Zebras"), "removed from conn")
        t.expectEqual(await store.saved(for: other).map(\.name), ["shared"], "other connection untouched")
    }

    await t.suite("SQLSavedQueryStore persists across instances") {
        // A fresh store over the same directory must load what the previous instances wrote.
        let reopened = SQLSavedQueryStore(directory: dir)
        let list = await reopened.saved(for: conn)
        t.expect(list.contains { $0.name == "apples" && $0.sql == "SELECT 99" }, "reloaded from disk")
    }
}
