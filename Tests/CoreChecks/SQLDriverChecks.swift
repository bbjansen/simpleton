// Tests/CoreChecks/SQLDriverChecks.swift
import Foundation
import SimpletonCore
import SimpletonSQL

func runSQLDriverChecks(_ t: TestRunner) async {
    t.suite("SQLValue.displayString") {
        t.expectEqual(SQLValue.null.displayString, "NULL", "null")
        t.expectEqual(SQLValue.integer(42).displayString, "42", "integer")
        t.expectEqual(SQLValue.text("hi").displayString, "hi", "text")
        t.expectEqual(SQLValue.bool(true).displayString, "true", "bool")
        t.expectEqual(SQLValue.blob(Data([1, 2, 3])).displayString, "<3 bytes>", "blob")
    }

    t.suite("QueryResult shapes") {
        let rows = QueryResult.rows(columns: [Column(name: "id")], rows: [[.integer(1)]])
        if case .rows(let cols, let r) = rows {
            t.expectEqual(cols.count, 1, "one column")
            t.expectEqual(r.count, 1, "one row")
        } else {
            t.expect(false, "expected .rows")
        }
        if case .status(let n, _) = QueryResult.status(affected: 3, message: "OK") {
            t.expectEqual(n, 3, "affected count")
        } else {
            t.expect(false, "expected .status")
        }
    }

    func tempDBPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("corechecks-sql-\(UUID().uuidString).sqlite").path
    }

    await t.suite("SQLiteDriver end-to-end") {
        let path = tempDBPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let driver = SQLiteDriver(path: path)
        do {
            try await driver.connect()
            _ = try await driver.run(
                "CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT NOT NULL, score REAL, note TEXT)")
            if case .status(let n, _) = try await driver.run(
                "INSERT INTO t (name, score, note) VALUES ('a', 1.5, NULL)")
            {
                t.expectEqual(n, 1, "insert affected 1")
            } else {
                t.expect(false, "insert should return .status")
            }
            if case .rows(let cols, let rows) = try await driver.run("SELECT id, name, score, note FROM t") {
                t.expectEqual(cols.map(\.name), ["id", "name", "score", "note"], "column names")
                t.expectEqual(rows.count, 1, "one row")
                t.expectEqual(rows[0][0], SQLValue.integer(1), "id integer")
                t.expectEqual(rows[0][1], SQLValue.text("a"), "name text")
                t.expectEqual(rows[0][2], SQLValue.double(1.5), "score double")
                t.expectEqual(rows[0][3], SQLValue.null, "note null")
            } else {
                t.expect(false, "select should return .rows")
            }
            let tables = try await driver.tables(in: nil)
            t.expect(tables.contains(TableInfo(name: "t", kind: .table)), "table t listed")
            let columns = try await driver.columns(of: "t", in: nil)
            t.expectEqual(columns.first?.name, "id", "first column id")
            t.expect(columns.first?.isPrimaryKey == true, "id is primary key")
            t.expect(columns.contains { $0.name == "name" && !$0.nullable }, "name is NOT NULL")
            await driver.close()
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    await t.suite("SQLQueryHistoryStore record/dedup/cap/persist") {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("corechecks-sqlhist-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        let store = SQLQueryHistoryStore(directory: dir)
        await store.record("SELECT 1", for: id)
        await store.record("SELECT 2", for: id)
        await store.record("SELECT 1", for: id)  // dedup → moves to front
        let h = await store.history(for: id)
        t.expectEqual(h.first, "SELECT 1", "most recent first after dedup")
        t.expectEqual(h.count, 2, "deduped to two entries")
        let reloaded = SQLQueryHistoryStore(directory: dir)
        t.expectEqual(await reloaded.history(for: id).count, 2, "persisted across instances")
    }

    t.suite("SQLDriverFactory mapping") {
        do {
            let sqlite = try SQLDriverFactory.make(
                Connection(name: "s", kind: .sqlite, params: ["path": "/tmp/x.sqlite"]), secret: nil)
            t.expect(sqlite is SQLiteDriver, "sqlite → SQLiteDriver")
        } catch {
            t.expect(false, "sqlite factory should not throw: \(error)")
        }
        do {
            _ = try SQLDriverFactory.make(Connection(name: "s3", kind: .s3), secret: nil)
            t.expect(false, "s3 should throw unsupported")
        } catch let e as SQLDriverError {
            if case .unsupported = e {
                t.expect(true, "s3 → unsupported")
            } else {
                t.expect(false, "wrong error \(e)")
            }
        } catch {
            t.expect(false, "wrong error type: \(error)")
        }
    }
}
