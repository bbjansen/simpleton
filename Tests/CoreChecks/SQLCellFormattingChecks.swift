import Foundation
import SimpletonSQL

func runSQLCellFormattingChecks(_ t: TestRunner) {
    t.suite("SQLCellFormatting.present") {
        let n = SQLCellFormatting.present(.integer(42))
        t.expectEqual(n.role, .number, "integer role")
        t.expectEqual(n.alignment, .trailing, "integer alignment")
        t.expectEqual(n.text, "42", "integer text")
        t.expect(!n.isNull, "integer not null")

        let d = SQLCellFormatting.present(.double(3.5))
        t.expectEqual(d.role, .number, "double role")
        t.expectEqual(d.alignment, .trailing, "double alignment")

        let s = SQLCellFormatting.present(.text("hi"))
        t.expectEqual(s.role, .text, "text role")
        t.expectEqual(s.alignment, .leading, "text alignment")
        t.expect(!s.isEmptyText, "non-empty text")

        let empty = SQLCellFormatting.present(.text(""))
        t.expect(empty.isEmptyText, "empty text flagged")
        t.expect(!empty.isNull, "empty text is not null")

        let b = SQLCellFormatting.present(.bool(true))
        t.expectEqual(b.role, .bool, "bool role")
        t.expectEqual(b.text, "true", "bool text")

        let bl = SQLCellFormatting.present(.blob(Data([1, 2, 3])))
        t.expectEqual(bl.role, .blob, "blob role")
        t.expectEqual(bl.text, "<3 bytes>", "blob text")

        let nul = SQLCellFormatting.present(.null)
        t.expectEqual(nul.role, .null, "null role")
        t.expect(nul.isNull, "null flagged")
        t.expectEqual(nul.text, "NULL", "null text")
    }

    t.suite("SQLCellFormatting.compare") {
        t.expectEqual(SQLCellFormatting.compare(.integer(2), .integer(10)), .orderedAscending, "2 < 10 numeric")
        t.expectEqual(SQLCellFormatting.compare(.integer(10), .integer(2)), .orderedDescending, "10 > 2")
        t.expectEqual(SQLCellFormatting.compare(.integer(2), .double(2.5)), .orderedAscending, "2 < 2.5 mixed")
        t.expectEqual(
            SQLCellFormatting.compare(.text("apple"), .text("Banana")), .orderedAscending, "apple < Banana ci")
        t.expectEqual(SQLCellFormatting.compare(.bool(false), .bool(true)), .orderedAscending, "false < true")
        t.expectEqual(
            SQLCellFormatting.compare(.blob(Data([1])), .blob(Data([1, 2]))), .orderedAscending, "1 byte < 2 bytes")
        t.expectEqual(SQLCellFormatting.compare(.integer(1), .null), .orderedAscending, "value before null")
        t.expectEqual(SQLCellFormatting.compare(.null, .integer(1)), .orderedDescending, "null after value")
        t.expectEqual(SQLCellFormatting.compare(.null, .null), .orderedSame, "null == null")
        t.expectEqual(SQLCellFormatting.compare(.integer(9), .text("a")), .orderedAscending, "number < text")
        t.expectEqual(SQLCellFormatting.compare(.text("z"), .bool(false)), .orderedAscending, "text < bool")
        t.expectEqual(SQLCellFormatting.compare(.bool(true), .blob(Data())), .orderedAscending, "bool < blob")
        // Large Int64s must not collapse through Double (52-bit mantissa) — 2^53 vs 2^53+1.
        t.expectEqual(
            SQLCellFormatting.compare(.integer(9_007_199_254_740_992), .integer(9_007_199_254_740_993)),
            .orderedAscending, "adjacent large Int64 distinct")
        t.expectEqual(
            SQLCellFormatting.compare(.integer(Int64.max), .integer(Int64.max - 1)),
            .orderedDescending, "Int64.max > max-1")
    }

    t.suite("SQLCellFormatting.prettyJSON") {
        let pretty = SQLCellFormatting.prettyJSON("{\"b\":1,\"a\":2}")
        t.expect(pretty != nil, "valid JSON object pretty-printed")
        t.expect(pretty?.contains("\n") ?? false, "pretty output is multi-line")
        // sortedKeys → "a" before "b"
        if let p = pretty, let ai = p.range(of: "\"a\""), let bi = p.range(of: "\"b\"") {
            t.expect(ai.lowerBound < bi.lowerBound, "keys sorted (a before b)")
        } else {
            t.expect(false, "expected both keys present")
        }
        t.expect(SQLCellFormatting.prettyJSON("[1, 2, 3]") != nil, "JSON array pretty-printed")
        t.expect(SQLCellFormatting.prettyJSON("hello world") == nil, "plain text → nil")
        t.expect(SQLCellFormatting.prettyJSON("{not json}") == nil, "malformed → nil")
        t.expect(SQLCellFormatting.prettyJSON("42") == nil, "bare number → nil (not object/array)")
    }

    t.suite("SQLCellFormatting.hexDump") {
        let dump = SQLCellFormatting.hexDump(Data([0x48, 0x69, 0x00, 0xff]))
        t.expect(dump.hasPrefix("00000000  48 69 00 ff"), "hex bytes at offset 0")
        t.expect(dump.contains("Hi.."), "ascii column (non-printable → .)")
        let big = SQLCellFormatting.hexDump(Data(repeating: 0, count: 5000), maxBytes: 4096)
        t.expect(big.contains("904 more bytes"), "truncation note for oversized blob")
    }
}
