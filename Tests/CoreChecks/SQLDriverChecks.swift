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
}
