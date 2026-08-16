// Sources/SimpletonSQL/SQLStatementSplitter.swift
import Foundation

/// Splits a SQL script into individual statements on top-level `;`. Semicolons inside string literals,
/// comments, and quoted identifiers do not split — the boundaries come from `SQLTokenizer`, so the
/// rule matches the editor's own lexing. Pure and headless, so the splitting is unit-tested without a
/// driver. Used to run a multi-statement script and show one result tab per statement.
public enum SQLStatementSplitter {
    /// Return the non-empty, trimmed statements in `sql`. A script with no top-level `;` yields one
    /// element (the whole trimmed text); trailing/empty fragments are dropped. Whitespace/comment-only
    /// input yields `[]`.
    public static func split(_ sql: String) -> [String] {
        let ns = sql as NSString
        guard ns.length > 0 else { return [] }
        // Offsets covered by a string / comment / quoted-identifier token, where a `;` is not a
        // separator. (Bare identifiers can't contain `;`, so including them is harmless.)
        let protectedRanges =
            SQLTokenizer.tokens(in: sql)
            .filter { $0.kind == .string || $0.kind == .comment || $0.kind == .identifier }
            .map { NSRange(location: $0.location, length: $0.length) }

        func isProtected(_ location: Int) -> Bool {
            protectedRanges.contains { location >= $0.location && location < $0.location + $0.length }
        }

        let semicolon = UInt16(UnicodeScalar(";").value)
        var statements: [String] = []
        var start = 0
        var i = 0
        func flush(upTo end: Int) {
            let fragment = ns.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !fragment.isEmpty { statements.append(fragment) }
        }
        while i < ns.length {
            if ns.character(at: i) == semicolon && !isProtected(i) {
                flush(upTo: i)
                start = i + 1
            }
            i += 1
        }
        flush(upTo: ns.length)
        return statements
    }
}
