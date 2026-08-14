import Foundation
import SimpletonSQL

func runSQLTokenizerChecks(_ t: TestRunner) {
    func text(_ tok: SQLToken, _ sql: String) -> String {
        (sql as NSString).substring(with: NSRange(location: tok.location, length: tok.length))
    }
    /// Find the first token whose text equals `s` (case-sensitive), returning its kind.
    func kind(of s: String, in sql: String) -> SQLTokenKind? {
        SQLTokenizer.tokens(in: sql).first { text($0, sql) == s }?.kind
    }

    t.suite("SQLTokenizer keywords + identifiers") {
        let sql = "SELECT id, name FROM users WHERE id = 5"
        t.expectEqual(kind(of: "SELECT", in: sql), .keyword, "SELECT is a keyword")
        t.expectEqual(kind(of: "FROM", in: sql), .keyword, "FROM is a keyword")
        t.expectEqual(kind(of: "WHERE", in: sql), .keyword, "WHERE is a keyword")
        t.expectEqual(kind(of: "users", in: sql), .identifier, "users is an identifier")
        t.expectEqual(kind(of: "name", in: sql), .identifier, "name is an identifier")
        t.expectEqual(kind(of: "5", in: sql), .number, "5 is a number")
    }

    t.suite("SQLTokenizer case-insensitive keywords") {
        t.expectEqual(kind(of: "select", in: "select 1"), .keyword, "lowercase keyword")
        t.expectEqual(kind(of: "Select", in: "Select 1"), .keyword, "mixed-case keyword")
    }

    t.suite("SQLTokenizer strings + escapes") {
        let sql = "SELECT 'hello'"
        t.expectEqual(kind(of: "'hello'", in: sql), .string, "single-quoted string")
        // '' escape keeps it one string token.
        let esc = "SELECT 'it''s'"
        let strings = SQLTokenizer.tokens(in: esc).filter { $0.kind == .string }
        t.expectEqual(strings.count, 1, "escaped '' stays one string")
        if let s = strings.first { t.expectEqual(text(s, esc), "'it''s'", "full escaped string captured") }
    }

    t.suite("SQLTokenizer comments") {
        t.expectEqual(kind(of: "-- a comment", in: "SELECT 1 -- a comment"), .comment, "line comment")
        let block = "/* multi\nline */ SELECT"
        let comments = SQLTokenizer.tokens(in: block).filter { $0.kind == .comment }
        t.expectEqual(comments.count, 1, "block comment is one token")
        if let c = comments.first { t.expectEqual(text(c, block), "/* multi\nline */", "block comment spans lines") }
    }

    t.suite("SQLTokenizer numbers + quoted identifiers") {
        t.expectEqual(kind(of: "3.14", in: "SELECT 3.14"), .number, "decimal number")
        t.expectEqual(kind(of: "\"my col\"", in: "SELECT \"my col\""), .identifier, "quoted identifier")
        t.expectEqual(kind(of: "`col`", in: "SELECT `col`"), .identifier, "backtick identifier")
    }
}
