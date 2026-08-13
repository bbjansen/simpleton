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
    }
}
