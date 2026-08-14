import Foundation
import SimpletonSQL

func runSQLGridDataChecks(_ t: TestRunner) {
    let columns = [Column(name: "id"), Column(name: "name")]
    let rows: [[SQLValue]] = [
        [.integer(10), .text("banana")],
        [.integer(2), .text("apple")],
        [.null, .text("cherry")],
    ]
    let data = SQLGridData(columns: columns, rows: rows)

    t.suite("SQLGridData basics") {
        t.expectEqual(data.rowCount, 3, "row count")
        t.expectEqual(data.columnCount, 2, "column count")
        t.expectEqual(data.value(row: 0, column: 0), SQLValue.integer(10), "value(0,0)")
        t.expectEqual(data.value(row: 99, column: 0), SQLValue.null, "OOB row -> null")
    }

    t.suite("SQLGridData.sortedIndex") {
        t.expectEqual(data.sortedIndex(sortColumn: nil, ascending: true), [0, 1, 2], "identity when unsorted")
        t.expectEqual(data.sortedIndex(sortColumn: 0, ascending: true), [1, 0, 2], "id asc, null last")
        t.expectEqual(data.sortedIndex(sortColumn: 0, ascending: false), [2, 0, 1], "id desc, null first")
        t.expectEqual(data.sortedIndex(sortColumn: 1, ascending: true), [1, 0, 2], "name asc")
    }

    t.suite("SQLGridData.tsv") {
        let order = data.sortedIndex(sortColumn: 0, ascending: true)  // [1, 0, 2]
        let out = data.tsv(rows: order, withHeader: true)
        let expected = "id\tname\n2\tapple\n10\tbanana\n\tcherry"
        t.expectEqual(out, expected, "tsv with header, null as empty")

        let quoted = SQLGridData(columns: [Column(name: "c")], rows: [[.text("a\tb")]])
        t.expectEqual(quoted.tsv(rows: [0], withHeader: false), "\"a\tb\"", "tab value quoted")

        let q2 = SQLGridData(columns: [Column(name: "c")], rows: [[.text("he said \"hi\"")]])
        t.expectEqual(q2.tsv(rows: [0], withHeader: false), "\"he said \"\"hi\"\"\"", "embedded quote doubled")

        let cr = SQLGridData(columns: [Column(name: "c")], rows: [[.text("a\rb")]])
        t.expectEqual(cr.tsv(rows: [0], withHeader: false), "\"a\rb\"", "carriage-return value quoted")
    }

    t.suite("SQLGridData.sortedIndex(by:) multi-key") {
        // group asc, then value desc within group.
        let cols = [Column(name: "g"), Column(name: "v")]
        let rs: [[SQLValue]] = [
            [.text("b"), .integer(1)],  // 0
            [.text("a"), .integer(2)],  // 1
            [.text("a"), .integer(5)],  // 2
            [.text("b"), .integer(9)],  // 3
        ]
        let d = SQLGridData(columns: cols, rows: rs)
        // g asc: a group (rows 1,2), b group (rows 0,3). v desc within: a→[5,2]=(2,1), b→[9,1]=(3,0)
        let keys = [SortKey(column: 0, ascending: true), SortKey(column: 1, ascending: false)]
        t.expectEqual(d.sortedIndex(by: keys), [2, 1, 3, 0], "g asc, then v desc within group")
        // empty keys → identity
        t.expectEqual(d.sortedIndex(by: []), [0, 1, 2, 3], "no keys → identity")
        // single key matches the convenience overload
        t.expectEqual(
            d.sortedIndex(by: [SortKey(column: 1, ascending: true)]),
            d.sortedIndex(sortColumn: 1, ascending: true), "multi wrapper == single")
    }

    t.suite("SQLGridData.enumColumns") {
        let cols = [Column(name: "id"), Column(name: "status"), Column(name: "n")]
        let rs: [[SQLValue]] = [
            [.text("a1"), .text("open"), .integer(1)],
            [.text("a2"), .text("closed"), .integer(2)],
            [.text("a3"), .text("open"), .integer(3)],
            [.text("a4"), .text("open"), .integer(4)],
        ]
        let d = SQLGridData(columns: cols, rows: rs)
        let enums = d.enumColumns(maxDistinct: 3)
        t.expect(enums.contains(1), "low-cardinality text column is an enum")
        t.expect(!enums.contains(0), "all-distinct text column is not an enum (exceeds maxDistinct)")
        t.expect(!enums.contains(2), "numeric column is never an enum")
        // stable color slot in range
        let slot = d.enumColorIndex("open", slots: 8)
        t.expect((0..<8).contains(slot), "color slot in range")
        t.expectEqual(d.enumColorIndex("open", slots: 8), slot, "color slot is deterministic")
    }

    t.suite("SQLGridData.columnSignature") {
        let a = SQLGridData(columns: [Column(name: "id"), Column(name: "name")], rows: [])
        let a2 = SQLGridData(columns: [Column(name: "id"), Column(name: "name")], rows: [[.integer(1)]])
        let b = SQLGridData(columns: [Column(name: "name"), Column(name: "id")], rows: [])
        t.expectEqual(a.columnSignature, a2.columnSignature, "signature ignores rows, same columns")
        t.expect(a.columnSignature != b.columnSignature, "column order changes the signature")
        t.expect(!a.columnSignature.isEmpty, "signature non-empty")
    }
}
