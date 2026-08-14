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

            // Parameterized execute round-trip: the value is BOUND (never interpolated), so a value
            // containing SQL metacharacters lands verbatim and cannot alter the statement.
            _ = try await driver.execute(
                "UPDATE t SET name = ?, score = ?, note = ? WHERE id = ?",
                [.text("x'; DROP TABLE t; --"), .double(2.5), .null, .integer(1)])
            if case .rows(_, let rows) = try await driver.run("SELECT name, score, note FROM t WHERE id = 1") {
                t.expectEqual(rows.count, 1, "row still present after bound UPDATE")
                t.expectEqual(rows.first?[0], SQLValue.text("x'; DROP TABLE t; --"), "text bound verbatim")
                t.expectEqual(rows.first?[1], SQLValue.double(2.5), "double bound")
                t.expectEqual(rows.first?[2], SQLValue.null, "null bound")
            } else {
                t.expect(false, "select after execute should return rows")
            }
            // The table must still exist — proof the injection-looking value never became SQL.
            t.expect(try await driver.tables(in: nil).contains { $0.name == "t" }, "table survives bound value")
            // Blob round-trip through the native bind.
            _ = try await driver.execute(
                "UPDATE t SET note = ? WHERE id = ?", [.blob(Data([0, 1, 2, 255])), .integer(1)])
            if case .rows(_, let rows) = try await driver.run("SELECT note FROM t WHERE id = 1") {
                t.expectEqual(rows.first?[0], SQLValue.blob(Data([0, 1, 2, 255])), "blob bound + read back")
            } else {
                t.expect(false, "select blob should return rows")
            }
            await driver.close()
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    await t.suite("SQLiteDriver foreignKeys(of:) round-trip") {
        let path = tempDBPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let driver = SQLiteDriver(path: path)
        do {
            try await driver.connect()
            // Two tables with an explicit FK: order.customer_id → customer.id (named ref column).
            _ = try await driver.run("CREATE TABLE customer (id INTEGER PRIMARY KEY, name TEXT)")
            _ = try await driver.run(
                "CREATE TABLE \"order\" (id INTEGER PRIMARY KEY, customer_id INTEGER, "
                    + "note TEXT, FOREIGN KEY(customer_id) REFERENCES customer(id))")
            let fks = try await driver.foreignKeys(of: "order", in: nil)
            t.expectEqual(fks.count, 1, "one FK on order")
            t.expectEqual(fks.first?.column, "customer_id", "local FK column")
            t.expectEqual(fks.first?.referencedTable, "customer", "referenced table")
            t.expectEqual(fks.first?.referencedColumn, "id", "referenced column")
            // A table with no FKs yields an empty list (not an error).
            t.expect(try await driver.foreignKeys(of: "customer", in: nil).isEmpty, "customer has no FKs")

            // End-to-end navigation shape: seed data and run the exact parameterized lookup the FK
            // jump issues, with the value BOUND — proving the referenced row comes back.
            _ = try await driver.run("INSERT INTO customer (id, name) VALUES (7, 'Ada')")
            _ = try await driver.run("INSERT INTO \"order\" (id, customer_id, note) VALUES (1, 7, 'x')")
            if case .rows(let cols, let rows) = try await driver.execute(
                "SELECT * FROM \"customer\" WHERE \"id\" = ?", [.integer(7)])
            {
                t.expectEqual(rows.count, 1, "one referenced row")
                if let nameIdx = cols.firstIndex(where: { $0.name == "name" }) {
                    t.expectEqual(rows.first?[nameIdx], SQLValue.text("Ada"), "referenced row is Ada")
                } else {
                    t.expect(false, "name column present")
                }
            } else {
                t.expect(false, "FK lookup should return rows")
            }
            await driver.close()
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    t.suite("SQLForeignKeyMatcher") {
        let fks = [
            ForeignKeyInfo(column: "customer_id", referencedTable: "customer", referencedColumn: "id"),
            ForeignKeyInfo(column: "product_id", referencedTable: "product", referencedColumn: "sku"),
        ]
        // Basic name match, in grid order, mapping to the right target.
        let m = SQLForeignKeyMatcher.matches(
            resultColumns: ["id", "customer_id", "note", "product_id"], foreignKeys: fks)
        t.expectEqual(m.count, 2, "two FK columns matched")
        t.expectEqual(m.first?.columnIndex, 1, "customer_id at grid index 1")
        t.expectEqual(m.first?.referencedTable, "customer", "→ customer")
        t.expectEqual(m.first?.referencedColumn, "id", "→ customer.id")
        t.expectEqual(m.last?.columnIndex, 3, "product_id at grid index 3")
        t.expectEqual(m.last?.referencedColumn, "sku", "→ product.sku")

        // Case-insensitive match tolerates catalog casing differences.
        let ci = SQLForeignKeyMatcher.matches(resultColumns: ["Customer_ID"], foreignKeys: fks)
        t.expectEqual(ci.count, 1, "case-insensitive FK match")
        t.expectEqual(ci.first?.referencedTable, "customer", "ci → customer")

        // A column not visible in the result yields no match.
        t.expect(
            SQLForeignKeyMatcher.matches(resultColumns: ["id", "note"], foreignKeys: fks).isEmpty,
            "no FK columns in result → no matches")

        // Empty inputs → empty result (both directions).
        t.expect(SQLForeignKeyMatcher.matches(resultColumns: [], foreignKeys: fks).isEmpty, "no columns")
        t.expect(
            SQLForeignKeyMatcher.matches(resultColumns: ["customer_id"], foreignKeys: []).isEmpty, "no FKs")

        // A composite FK (same local column referenced twice) is NOT single-column navigable → skipped.
        let composite = [
            ForeignKeyInfo(column: "a_id", referencedTable: "t", referencedColumn: "x"),
            ForeignKeyInfo(column: "a_id", referencedTable: "t", referencedColumn: "y"),
        ]
        t.expect(
            SQLForeignKeyMatcher.matches(resultColumns: ["a_id"], foreignKeys: composite).isEmpty,
            "composite FK column is not offered")
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

    func parseSQLURL(_ raw: String, kind: ConnectionKind) -> (Connection, ConnectionSecret?)? {
        guard let c = URLComponents(string: raw), let host = c.host else { return nil }
        let db = c.path.hasPrefix("/") ? String(c.path.dropFirst()) : c.path
        let conn = Connection(
            name: "test", kind: kind, host: host, port: c.port,
            username: c.user, params: ["database": db, "useTLS": "false"])
        let secret = c.password.map { ConnectionSecret(password: $0) }
        return (conn, secret)
    }

    if let url = ProcessInfo.processInfo.environment["SIMPLETON_PG_TEST_URL"],
        let (conn, secret) = parseSQLURL(url, kind: .postgres)
    {
        await t.suite("PostgresDriver SELECT 1 (integration)") {
            do {
                let driver = try SQLDriverFactory.make(conn, secret: secret)
                try await driver.connect()
                if case .rows(let cols, let rows) = try await driver.run("SELECT 1 AS n") {
                    t.expectEqual(cols.first?.name, "n", "column name n")
                    t.expectEqual(rows.first?.first, SQLValue.integer(1), "value 1")
                } else {
                    t.expect(false, "SELECT should return rows")
                }
                _ = try await driver.tables(in: nil)  // smoke: schema query runs
                await driver.close()
            } catch {
                t.expect(false, "unexpected error: \(error)")
            }
        }
    } else {
        print("  … PostgresDriver checks skipped (set SIMPLETON_PG_TEST_URL to run)")
    }

    if let url = ProcessInfo.processInfo.environment["SIMPLETON_MYSQL_TEST_URL"],
        let (conn, secret) = parseSQLURL(url, kind: .mysql)
    {
        await t.suite("MySQLDriver SELECT 1 (integration)") {
            do {
                let driver = try SQLDriverFactory.make(conn, secret: secret)
                try await driver.connect()
                if case .rows(let cols, let rows) = try await driver.run("SELECT 1 AS n") {
                    t.expectEqual(cols.first?.name, "n", "column name n")
                    t.expectEqual(rows.first?.first?.displayString, "1", "value 1")
                } else {
                    t.expect(false, "SELECT should return rows")
                }
                _ = try await driver.tables(in: nil)
                await driver.close()
            } catch {
                t.expect(false, "unexpected error: \(error)")
            }
        }
    } else {
        print("  … MySQLDriver checks skipped (set SIMPLETON_MYSQL_TEST_URL to run)")
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
