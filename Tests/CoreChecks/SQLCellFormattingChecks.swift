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
    }
}
