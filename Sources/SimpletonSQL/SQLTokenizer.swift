// Sources/SimpletonSQL/SQLTokenizer.swift
import Foundation

/// A lexical classification of a run of SQL text, used to drive editor syntax highlighting. Only the
/// highlighted kinds are emitted; whitespace/operators are left for the default color.
public enum SQLTokenKind: Sendable, Hashable {
    case keyword, string, comment, number, identifier
}

/// One classified token. `location`/`length` are **UTF-16 offsets** (matching `NSString`/`NSTextView`)
/// so the AppKit editor can apply attributes directly without re-mapping indices.
public struct SQLToken: Sendable, Hashable {
    public let location: Int
    public let length: Int
    public let kind: SQLTokenKind
    public init(location: Int, length: Int, kind: SQLTokenKind) {
        self.location = location
        self.length = length
        self.kind = kind
    }
}

/// A single-pass SQL lexer: keywords (case-insensitive), single-quoted strings (with `''` escapes),
/// `--` line + `/* */` block comments, numbers, and identifiers (incl. quoted `"…"` / `` `…` ``).
/// Pure and headless so highlighting is testable without a UI.
public enum SQLTokenizer {

    /// Common SQL keywords (upper-cased; matched case-insensitively).
    public static let keywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE",
        "TABLE", "VIEW", "INDEX", "DROP", "ALTER", "ADD", "COLUMN", "PRIMARY", "KEY", "FOREIGN",
        "REFERENCES", "UNIQUE", "NOT", "NULL", "DEFAULT", "AUTOINCREMENT", "AUTO_INCREMENT", "AND",
        "OR", "IN", "IS", "LIKE", "BETWEEN", "EXISTS", "JOIN", "INNER", "LEFT", "RIGHT", "OUTER",
        "FULL", "CROSS", "ON", "USING", "GROUP", "BY", "HAVING", "ORDER", "ASC", "DESC", "LIMIT",
        "OFFSET", "DISTINCT", "AS", "UNION", "ALL", "EXCEPT", "INTERSECT", "CASE", "WHEN", "THEN",
        "ELSE", "END", "CAST", "COUNT", "SUM", "AVG", "MIN", "MAX", "COALESCE", "BEGIN", "COMMIT",
        "ROLLBACK", "TRANSACTION", "WITH", "RETURNING", "TRUE", "FALSE", "INT", "INTEGER", "TEXT",
        "REAL", "BLOB", "VARCHAR", "CHAR", "BOOLEAN", "BOOL", "DATE", "TIMESTAMP", "SERIAL", "IF",
    ]

    public static func tokens(in sql: String) -> [SQLToken] {
        var result: [SQLToken] = []
        let scalars = Array(sql.unicodeScalars)
        var i = 0
        var utf16 = 0  // running UTF-16 offset

        func u16(_ s: Unicode.Scalar) -> Int { s.value > 0xFFFF ? 2 : 1 }

        func isIdentStart(_ s: Unicode.Scalar) -> Bool {
            (s >= "a" && s <= "z") || (s >= "A" && s <= "Z") || s == "_"
        }
        func isIdentChar(_ s: Unicode.Scalar) -> Bool {
            isIdentStart(s) || (s >= "0" && s <= "9")
        }
        func isDigit(_ s: Unicode.Scalar) -> Bool { s >= "0" && s <= "9" }

        while i < scalars.count {
            let s = scalars[i]
            let start = utf16

            // Line comment: -- … EOL
            if s == "-", i + 1 < scalars.count, scalars[i + 1] == "-" {
                var len = 0
                while i < scalars.count, scalars[i] != "\n" {
                    len += u16(scalars[i])
                    i += 1
                }
                result.append(SQLToken(location: start, length: len, kind: .comment))
                utf16 = start + len
                continue
            }
            // Block comment: /* … */
            if s == "/", i + 1 < scalars.count, scalars[i + 1] == "*" {
                var len = 0
                var closed = false
                while i < scalars.count {
                    if scalars[i] == "*", i + 1 < scalars.count, scalars[i + 1] == "/" {
                        len += u16(scalars[i]) + u16(scalars[i + 1])
                        i += 2
                        closed = true
                        break
                    }
                    len += u16(scalars[i])
                    i += 1
                }
                _ = closed
                result.append(SQLToken(location: start, length: len, kind: .comment))
                utf16 = start + len
                continue
            }
            // Single-quoted string with '' escapes.
            if s == "'" {
                var len = u16(s)
                i += 1
                while i < scalars.count {
                    if scalars[i] == "'" {
                        // '' is an escaped quote → consume both and continue inside the string.
                        if i + 1 < scalars.count, scalars[i + 1] == "'" {
                            len += u16(scalars[i]) + u16(scalars[i + 1])
                            i += 2
                            continue
                        }
                        len += u16(scalars[i])
                        i += 1
                        break
                    }
                    len += u16(scalars[i])
                    i += 1
                }
                result.append(SQLToken(location: start, length: len, kind: .string))
                utf16 = start + len
                continue
            }
            // Quoted / backtick identifier.
            if s == "\"" || s == "`" {
                let close = s
                var len = u16(s)
                i += 1
                while i < scalars.count {
                    len += u16(scalars[i])
                    let c = scalars[i]
                    i += 1
                    if c == close { break }
                }
                result.append(SQLToken(location: start, length: len, kind: .identifier))
                utf16 = start + len
                continue
            }
            // Number.
            if isDigit(s) {
                var len = 0
                while i < scalars.count,
                    isDigit(scalars[i]) || scalars[i] == "." || scalars[i] == "e" || scalars[i] == "E"
                {
                    len += u16(scalars[i])
                    i += 1
                }
                result.append(SQLToken(location: start, length: len, kind: .number))
                utf16 = start + len
                continue
            }
            // Identifier / keyword.
            if isIdentStart(s) {
                var len = 0
                var word = ""
                while i < scalars.count, isIdentChar(scalars[i]) {
                    word.unicodeScalars.append(scalars[i])
                    len += u16(scalars[i])
                    i += 1
                }
                let kind: SQLTokenKind = keywords.contains(word.uppercased()) ? .keyword : .identifier
                result.append(SQLToken(location: start, length: len, kind: kind))
                utf16 = start + len
                continue
            }
            // Anything else (whitespace, operators, punctuation) → default color; advance one scalar.
            utf16 += u16(s)
            i += 1
        }
        return result
    }
}
