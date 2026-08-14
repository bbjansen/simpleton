import Foundation
import SimpletonSQL

func runSQLResultExporterChecks(_ t: TestRunner) {
    let columns = [Column(name: "id"), Column(name: "name")]
    let rows: [[SQLValue]] = [
        [.integer(1), .text("apple")],
        [.integer(2), .null],
    ]

    t.suite("SQLResultExporter CSV basics") {
        let csv = SQLResultExporter.csv(columns: columns, rows: rows)
        t.expectEqual(csv, "id,name\r\n1,apple\r\n2,", "header + rows, NULL empty, CRLF")
    }

    t.suite("SQLResultExporter CSV escaping (RFC 4180)") {
        let cols = [Column(name: "a"), Column(name: "b")]
        let data: [[SQLValue]] = [[.text("x,y"), .text("he said \"hi\"")], [.text("line1\nline2"), .text("plain")]]
        let csv = SQLResultExporter.csv(columns: cols, rows: data)
        let expected = "a,b\r\n\"x,y\",\"he said \"\"hi\"\"\"\r\n\"line1\nline2\",plain"
        t.expectEqual(csv, expected, "comma/quote/newline fields quoted, quotes doubled")
    }

    t.suite("SQLResultExporter CSV blob → base64") {
        let cols = [Column(name: "data")]
        let bytes = SQLResultExporter.csv(columns: cols, rows: [[.blob(Data([0x00, 0x01, 0xFF]))]])
        t.expectEqual(bytes, "data\r\nAAH/", "blob base64-encoded in CSV")
    }

    t.suite("SQLResultExporter JSON types + round-trip") {
        let cols = [
            Column(name: "i"), Column(name: "d"), Column(name: "s"), Column(name: "b"), Column(name: "n"),
        ]
        let data: [[SQLValue]] = [[.integer(7), .double(3.5), .text("hi \"q\"\n"), .bool(true), .null]]
        let json = SQLResultExporter.json(columns: cols, rows: data)
        // Parse it back — the strongest correctness check: valid JSON with the right typed values.
        guard let parsed = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]],
            let first = parsed.first
        else {
            t.expect(false, "emitted JSON parses to an array of objects")
            return
        }
        t.expectEqual(parsed.count, 1, "one object")
        t.expectEqual(first["i"] as? Int, 7, "integer stays a JSON number")
        t.expectEqual(first["d"] as? Double, 3.5, "double stays a JSON number")
        t.expectEqual(first["s"] as? String, "hi \"q\"\n", "text escapes round-trip")
        t.expectEqual(first["b"] as? Bool, true, "bool stays a JSON bool")
        t.expect(first["n"] is NSNull, "NULL becomes JSON null")
    }

    t.suite("SQLResultExporter JSON column order + non-finite double") {
        let cols = [Column(name: "z"), Column(name: "a")]
        let json = SQLResultExporter.json(columns: cols, rows: [[.integer(1), .double(.infinity)]])
        // Column order preserved (z before a); non-finite double falls back to a string.
        t.expectEqual(json, "[{\"z\":1,\"a\":\"inf\"}]", "order preserved, non-finite double → string")
    }

    t.suite("SQLResultExporter empty result") {
        let cols = [Column(name: "id")]
        t.expectEqual(SQLResultExporter.csv(columns: cols, rows: []), "id", "CSV of no rows is just the header")
        t.expectEqual(SQLResultExporter.json(columns: cols, rows: []), "[]", "JSON of no rows is an empty array")
    }
}
