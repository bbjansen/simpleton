// Tests/CoreChecks/SQLEditableQueryChecks.swift
import Foundation
import SimpletonSQL

/// Headless checks for the two pure pieces behind SQL inline editing: the conservative
/// editable-query parser (which SELECTs are single-table-updatable) and the parameterized UPDATE
/// builder (which must emit placeholders + a matching params array, never interpolate values).
func runSQLEditableQueryChecks(_ t: TestRunner) {
    t.suite("SQLEditableParser — editable single-table SELECTs") {
        func table(_ sql: String) -> String? { SQLEditableParser.parse(sql)?.table }
        func projection(_ sql: String) -> ParsedProjection? { SQLEditableParser.parse(sql)?.projection }

        t.expectEqual(table("SELECT * FROM users"), "users", "star select")
        t.expectEqual(projection("SELECT * FROM users"), ParsedProjection.all, "star projection")
        t.expectEqual(table("select * from users where id = 5"), "users", "lowercased + where")
        t.expectEqual(table("SELECT * FROM users LIMIT 100"), "users", "with LIMIT")
        t.expectEqual(
            table("SELECT * FROM users ORDER BY name LIMIT 10 OFFSET 5"), "users", "order/limit/offset")
        t.expectEqual(
            projection("SELECT id, name FROM users WHERE active = 1 ORDER BY id"),
            ParsedProjection.columns(["id", "name"]), "named columns + where/order")
        t.expectEqual(
            projection("SELECT \"id\", \"full name\" FROM users"),
            ParsedProjection.columns(["id", "full name"]), "quoted identifiers unquoted")
        // A comma inside a string literal must not be read as a projection separator or comma-join.
        t.expectEqual(table("SELECT * FROM users WHERE name = 'a,b'"), "users", "comma inside literal")
        // A column whose name merely contains a keyword substring is fine (word-boundary matching).
        t.expectEqual(
            projection("SELECT grouping_id FROM users"),
            ParsedProjection.columns(["grouping_id"]), "keyword substring in column name")
    }

    t.suite("SQLEditableParser — non-editable shapes reject to nil") {
        func isNil(_ sql: String) -> Bool { SQLEditableParser.parse(sql) == nil }
        t.expect(isNil("SELECT * FROM users u JOIN orders o ON u.id = o.uid"), "explicit JOIN")
        t.expect(isNil("SELECT * FROM users, orders"), "comma join")
        t.expect(isNil("SELECT COUNT(*) FROM users"), "aggregate COUNT(*)")
        t.expect(isNil("SELECT id, COUNT(*) FROM users GROUP BY id"), "GROUP BY + aggregate")
        t.expect(isNil("SELECT DISTINCT name FROM users"), "DISTINCT")
        t.expect(isNil("SELECT * FROM users UNION SELECT * FROM admins"), "UNION")
        t.expect(isNil("SELECT * FROM (SELECT * FROM users) t"), "subquery in FROM")
        t.expect(isNil("SELECT u.id FROM users u"), "table alias + qualified column")
        t.expect(isNil("SELECT id AS x FROM users"), "column alias")
        t.expect(isNil("SELECT id + 1 FROM users"), "expression column")
        t.expect(isNil("SELECT upper(name) FROM users"), "function call column")
        t.expect(isNil("SELECT * FROM users; DROP TABLE users"), "second statement")
        t.expect(isNil("SELECT * FROM users HAVING id > 1"), "HAVING")
        t.expect(isNil("WITH x AS (SELECT 1) SELECT * FROM x"), "CTE / WITH")
        t.expect(isNil("SELECT * FROM schema.users"), "schema-qualified table")
        t.expect(isNil("SELECT id, name, FROM users"), "trailing comma in projection")
        t.expect(isNil("SELECT * FROM users GROUP BY id"), "GROUP BY")
        t.expect(isNil("EXPLAIN SELECT * FROM users"), "EXPLAIN prefix")
        t.expect(isNil("PRAGMA table_info(users)"), "PRAGMA")
        t.expect(isNil(""), "empty string")
        t.expect(isNil("SELECT * FROM users u, orders o"), "two aliased tables")
    }

    t.suite("SQLUpdateBuilder — parameterized, no interpolation") {
        // SQLite/MySQL use ? placeholders; the params array carries the values, in order.
        do {
            let stmt = try SQLUpdateBuilder.build(
                table: "users",
                changes: [("name", .text("O'Brien")), ("score", .double(9.5))],
                keys: [("id", .integer(42))],
                dialect: .sqlite)
            t.expectEqual(
                stmt.sql, "UPDATE \"users\" SET \"name\" = ?, \"score\" = ? WHERE \"id\" = ?",
                "sqlite UPDATE shape")
            t.expectEqual(stmt.params.count, 3, "one param per placeholder")
            t.expectEqual(
                stmt.params, [.text("O'Brien"), .double(9.5), .integer(42)], "SET values then WHERE values")
            // The value with a quote must appear ONLY in params, never in the SQL text.
            t.expect(!stmt.sql.contains("O'Brien"), "value never interpolated into SQL")
            t.expectEqual(stmt.sql.filter { $0 == "?" }.count, stmt.params.count, "placeholder count == params")
        } catch {
            t.expect(false, "sqlite build threw: \(error)")
        }

        // Postgres uses $1.. numbered placeholders and double-quoted identifiers.
        do {
            let stmt = try SQLUpdateBuilder.build(
                table: "orders",
                changes: [("status", .text("shipped"))],
                keys: [("tenant", .integer(1)), ("id", .integer(7))],
                dialect: .postgres)
            t.expectEqual(
                stmt.sql,
                "UPDATE \"orders\" SET \"status\" = $1 WHERE \"tenant\" = $2 AND \"id\" = $3",
                "postgres numbered placeholders + composite key")
            t.expectEqual(stmt.params, [.text("shipped"), .integer(1), .integer(7)], "params in order")
        } catch {
            t.expect(false, "postgres build threw: \(error)")
        }

        // MySQL uses ? placeholders and backtick identifiers.
        do {
            let stmt = try SQLUpdateBuilder.build(
                table: "items", changes: [("qty", .integer(3))], keys: [("id", .integer(9))],
                dialect: .mysql)
            t.expectEqual(stmt.sql, "UPDATE `items` SET `qty` = ? WHERE `id` = ?", "mysql backtick quoting")
            t.expectEqual(stmt.params, [.integer(3), .integer(9)], "mysql params")
        } catch {
            t.expect(false, "mysql build threw: \(error)")
        }

        // Identifier quote-escaping: a column/table name containing the quote char is doubled.
        do {
            let stmt = try SQLUpdateBuilder.build(
                table: "we\"ird", changes: [("a\"b", .null)], keys: [("id", .integer(1))],
                dialect: .postgres)
            t.expectEqual(
                stmt.sql, "UPDATE \"we\"\"ird\" SET \"a\"\"b\" = $1 WHERE \"id\" = $2",
                "doubled double-quotes in identifiers")
        } catch {
            t.expect(false, "quote-escaping build threw: \(error)")
        }

        // Guards: no changes / no key.
        do {
            _ = try SQLUpdateBuilder.build(table: "t", changes: [], keys: [("id", .integer(1))], dialect: .sqlite)
            t.expect(false, "empty changes should throw")
        } catch let e as SQLUpdateBuilder.BuildError {
            t.expectEqual(e, .noChanges, "noChanges error")
        } catch {
            t.expect(false, "wrong error for empty changes: \(error)")
        }
        do {
            _ = try SQLUpdateBuilder.build(
                table: "t", changes: [("a", .integer(1))], keys: [], dialect: .sqlite)
            t.expect(false, "empty keys should throw")
        } catch let e as SQLUpdateBuilder.BuildError {
            t.expectEqual(e, .noKey, "noKey error")
        } catch {
            t.expect(false, "wrong error for empty keys: \(error)")
        }
    }
}
