import Foundation
import SimpletonSQL

func runSQLStatementSplitterChecks(_ t: TestRunner) {
    t.suite("SQLStatementSplitter basics") {
        t.expectEqual(SQLStatementSplitter.split("SELECT 1; SELECT 2"), ["SELECT 1", "SELECT 2"], "two statements")
        t.expectEqual(SQLStatementSplitter.split("SELECT 1"), ["SELECT 1"], "single statement, no semicolon")
        t.expectEqual(SQLStatementSplitter.split("SELECT 1;"), ["SELECT 1"], "trailing semicolon dropped")
        t.expectEqual(SQLStatementSplitter.split("   ;;  "), [], "only separators / whitespace → empty")
        t.expectEqual(SQLStatementSplitter.split(""), [], "empty input → empty")
    }

    t.suite("SQLStatementSplitter ignores ; in strings + comments") {
        t.expectEqual(
            SQLStatementSplitter.split("SELECT ';'; SELECT 2"),
            ["SELECT ';'", "SELECT 2"], "semicolon inside a string does not split")
        t.expectEqual(
            SQLStatementSplitter.split("SELECT 1 -- a; b\n; SELECT 2"),
            ["SELECT 1 -- a; b", "SELECT 2"], "semicolon inside a line comment does not split")
        t.expectEqual(
            SQLStatementSplitter.split("SELECT /* a; b */ 1; SELECT 2"),
            ["SELECT /* a; b */ 1", "SELECT 2"], "semicolon inside a block comment does not split")
    }

    t.suite("SQLStatementSplitter ignores ; in quoted identifiers") {
        t.expectEqual(
            SQLStatementSplitter.split("SELECT 1 AS \"a;b\"; SELECT 2"),
            ["SELECT 1 AS \"a;b\"", "SELECT 2"], "semicolon inside a quoted identifier does not split")
    }

    t.suite("SQLStatementSplitter trims whitespace + blank fragments") {
        t.expectEqual(
            SQLStatementSplitter.split("  SELECT 1 ;\n\n SELECT 2 ;\n"),
            ["SELECT 1", "SELECT 2"], "each statement trimmed, blank tail dropped")
        t.expectEqual(
            SQLStatementSplitter.split("SELECT 1;; SELECT 2"),
            ["SELECT 1", "SELECT 2"], "empty statement between semicolons dropped")
    }
}
