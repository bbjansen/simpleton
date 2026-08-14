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

    t.suite("SQLPaging.pageCount") {
        t.expectEqual(SQLPaging.pageCount(total: 0, pageSize: 500), 1, "empty result → 1 page")
        t.expectEqual(SQLPaging.pageCount(total: 100, pageSize: 500), 1, "fits in one page")
        t.expectEqual(SQLPaging.pageCount(total: 500, pageSize: 500), 1, "exact multiple, one page")
        t.expectEqual(SQLPaging.pageCount(total: 501, pageSize: 500), 2, "one over → two pages")
        t.expectEqual(SQLPaging.pageCount(total: 1200, pageSize: 500), 3, "partial last page")
        t.expectEqual(SQLPaging.pageCount(total: 1200, pageSize: nil), 1, "nil size → All → 1 page")
        t.expectEqual(SQLPaging.pageCount(total: 1200, pageSize: 0), 1, "zero size → All → 1 page")
    }

    t.suite("SQLPaging.bounds") {
        let b0 = SQLPaging.bounds(total: 1200, pageSize: 500, page: 0)
        t.expectEqual(b0.start, 0, "page 0 start")
        t.expectEqual(b0.end, 500, "page 0 end")
        t.expectEqual(b0.count, 500, "page 0 count")
        t.expectEqual(b0.firstRowNumber, 1, "page 0 first row #")
        t.expectEqual(b0.lastRowNumber, 500, "page 0 last row #")

        let b2 = SQLPaging.bounds(total: 1200, pageSize: 500, page: 2)
        t.expectEqual(b2.start, 1000, "last page start")
        t.expectEqual(b2.end, 1200, "last page end clamps to total")
        t.expectEqual(b2.count, 200, "last page partial count")

        // Out-of-range page clamps to the last valid page (result shrank / stale index).
        let over = SQLPaging.bounds(total: 1200, pageSize: 500, page: 9)
        t.expectEqual(over.page, 2, "over-range page clamps to last")
        t.expectEqual(over.start, 1000, "clamped page start")

        // Negative page clamps to 0.
        let neg = SQLPaging.bounds(total: 1200, pageSize: 500, page: -3)
        t.expectEqual(neg.page, 0, "negative page clamps to first")

        // "All" (nil / 0) → whole range on page 0.
        let all = SQLPaging.bounds(total: 1200, pageSize: nil, page: 5)
        t.expectEqual(all.start, 0, "All start")
        t.expectEqual(all.end, 1200, "All end = total")
        t.expectEqual(all.page, 0, "All page index is 0")

        // Empty result → empty page.
        let empty = SQLPaging.bounds(total: 0, pageSize: 500, page: 0)
        t.expect(empty.isEmpty, "empty result → empty page")
        t.expectEqual(empty.firstRowNumber, 0, "empty page first row # is 0")
    }

    t.suite("SQLGridData.tsv rectangular") {
        let cols = [Column(name: "id"), Column(name: "name"), Column(name: "note")]
        let rs: [[SQLValue]] = [
            [.integer(1), .text("alpha"), .null],
            [.integer(2), .text("beta"), .text("hi")],
            [.integer(3), .text("gamma"), .text("yo")],
        ]
        let d = SQLGridData(columns: cols, rows: rs)
        // Rows 1,2 (original) × columns 1,2 — a rubber-band rectangle, no header.
        let rect = d.tsv(rows: [1, 2], columns: [1, 2], withHeader: false)
        t.expectEqual(rect, "beta\thi\ngamma\tyo", "rectangular subset, ordered")
        // NULL cell stays an empty field inside the rectangle.
        let withNull = d.tsv(rows: [0], columns: [1, 2], withHeader: false)
        t.expectEqual(withNull, "alpha\t", "rectangular null → empty field")
        // Header uses only the selected columns.
        let hdr = d.tsv(rows: [0], columns: [0, 2], withHeader: true)
        t.expectEqual(hdr, "id\tnote\n1\t", "rectangular header = selected columns only")
        // Out-of-range column indices are skipped.
        let clamped = d.tsv(rows: [1], columns: [1, 9], withHeader: false)
        t.expectEqual(clamped, "beta", "out-of-range column skipped")
        // Whole-column set matches the whole-row tsv overload.
        t.expectEqual(
            d.tsv(rows: [0, 1], columns: [0, 1, 2], withHeader: true),
            d.tsv(rows: [0, 1], withHeader: true), "full column set == whole-row tsv")
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
