// Sources/SimpletonSQL/SQLEditableQuery.swift
import Foundation

/// The column list a SELECT projects, as understood by the conservative editable-query parser.
public enum ParsedProjection: Sendable, Hashable {
    /// `SELECT *` — the concrete columns come from the result/schema, not the query text.
    case all
    /// `SELECT a, b, c` — a list of bare column identifiers (no expressions/aliases/qualifiers).
    case columns([String])
}

/// A parsed single-table SELECT that *may* be editable. Only produced for queries the parser is
/// confident about; anything ambiguous yields `nil` (a false negative — safe — never a false
/// positive, which would let an edit target the wrong rows).
public struct ParsedSelect: Sendable, Hashable {
    public let table: String
    public let projection: ParsedProjection
    public init(table: String, projection: ParsedProjection) {
        self.table = table
        self.projection = projection
    }
}

/// Decides whether a query's *shape* permits row editing. Deliberately conservative: it only accepts
/// a plain `SELECT <cols|*> FROM <table> [WHERE/ORDER BY/LIMIT/OFFSET …]` over ONE real table with no
/// joins, comma-lists, set operations, grouping, DISTINCT, aggregates, or subqueries. Everything else
/// is rejected. This is a pure function so it can be unit-tested headlessly.
public enum SQLEditableParser {
    /// Keywords that, appearing anywhere as a whole word before/within the FROM clause, make the
    /// result ambiguous to map back to single-table rows. Detected case-insensitively on word
    /// boundaries so column names containing these substrings (e.g. `grouping_id`) don't trip it.
    private static let disqualifyingKeywords: Set<String> = [
        "join", "union", "intersect", "except", "group", "distinct", "having", "over", "window",
    ]

    /// Aggregate/window function names that make a projected column non-updatable.
    private static let aggregateFunctions: Set<String> = [
        "count", "sum", "avg", "min", "max", "total", "group_concat", "array_agg", "string_agg",
        "json_agg", "jsonb_agg", "stddev", "variance", "var_pop", "var_samp",
    ]

    public static func parse(_ rawSQL: String) -> ParsedSelect? {
        // 1. Single statement only. Strip a single trailing ';', reject anything with an interior ';'
        //    (which could smuggle a second statement into the editable path).
        var sql = rawSQL.trimmingCharacters(in: .whitespacesAndNewlines)
        while sql.hasSuffix(";") { sql = String(sql.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !sql.isEmpty, !sql.contains(";") else { return nil }

        // 2. Must start with SELECT (not WITH/EXPLAIN/PRAGMA/etc.).
        let lower = sql.lowercased()
        guard lower.hasPrefix("select") else { return nil }
        // Guard the boundary so "selecting" isn't mistaken for "select ".
        let afterSelectIndex = sql.index(sql.startIndex, offsetBy: 6)
        guard afterSelectIndex < sql.endIndex, sql[afterSelectIndex].isWhitespace else { return nil }

        // 3. Split the projection (between SELECT and the top-level FROM) from the tail (FROM onward).
        guard let fromRange = topLevelKeywordRange(in: sql, keyword: "from") else { return nil }
        let projectionText = String(sql[sql.index(afterSelectIndex, offsetBy: 0)..<fromRange.lowerBound])
        let tail = String(sql[fromRange.upperBound...])

        // 4. Reject disqualifying keywords in either fragment (join/union/group/distinct/…). A bare
        //    parenthesis in the projection or FROM signals a subquery or function call we won't map.
        guard !containsDisqualifier(projectionText), !containsDisqualifier(tail) else { return nil }
        guard !tail.contains("(") else { return nil }  // no subquery / function in FROM

        // 5. Parse the FROM tail: exactly one table identifier, then only WHERE/ORDER BY/LIMIT/OFFSET.
        guard let table = singleTable(from: tail) else { return nil }

        // 6. Parse the projection: `*` or a comma list of bare identifiers (no expressions).
        guard let projection = parseProjection(projectionText) else { return nil }

        return ParsedSelect(table: table, projection: projection)
    }

    /// The range of a top-level (paren-depth 0) whole-word keyword, matched case-insensitively.
    private static func topLevelKeywordRange(in sql: String, keyword: String) -> Range<String.Index>? {
        let chars = Array(sql)
        let kw = Array(keyword.lowercased())
        var depth = 0
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "(" {
                depth += 1
            } else if c == ")" {
                depth = max(0, depth - 1)
            }
            if depth == 0, i + kw.count <= chars.count {
                var match = true
                for j in 0..<kw.count where Character(String(chars[i + j]).lowercased()) != kw[j] {
                    match = false
                    break
                }
                if match {
                    let beforeOK = i == 0 || !isIdentChar(chars[i - 1])
                    let afterIdx = i + kw.count
                    let afterOK = afterIdx >= chars.count || !isIdentChar(chars[afterIdx])
                    if beforeOK, afterOK {
                        let lower = sql.index(sql.startIndex, offsetBy: i)
                        let upper = sql.index(sql.startIndex, offsetBy: afterIdx)
                        return lower..<upper
                    }
                }
            }
            i += 1
        }
        return nil
    }

    /// True if any disqualifying keyword appears as a whole word (case-insensitive) in `fragment`.
    private static func containsDisqualifier(_ fragment: String) -> Bool {
        let words = tokenizeWords(fragment.lowercased())
        if !words.isDisjoint(with: disqualifyingKeywords) { return true }
        // A comma in the top-level projection or FROM means a column list of expressions or an
        // old-style comma join — both are rejected. (Projection commas are handled in parseProjection,
        // but a comma in the FROM tail is always a comma-join.)
        return false
    }

    /// A single table name from the FROM tail, or nil if there's a join, comma-list, alias, subquery,
    /// schema-qualified name we won't touch, or trailing clauses other than WHERE/ORDER/LIMIT/OFFSET.
    private static func singleTable(from tail: String) -> String? {
        let trimmed = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Take everything up to the first top-level clause keyword (WHERE/ORDER/LIMIT/OFFSET/GROUP).
        var tableClause = trimmed
        for kw in ["where", "order", "limit", "offset", "group", "having", "union"] {
            if let r = topLevelKeywordRange(in: tableClause, keyword: kw) {
                tableClause = String(tableClause[..<r.lowerBound])
            }
        }
        tableClause = tableClause.trimmingCharacters(in: .whitespacesAndNewlines)
        // No comma (comma-join) and exactly one whitespace-free token (no alias like `t x`, no `AS`).
        guard !tableClause.contains(",") else { return nil }
        let tokens = tableClause.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard tokens.count == 1 else { return nil }
        return normalizeIdentifier(tokens[0])
    }

    /// Parse the projection between SELECT and FROM: `*`, or a comma list of bare column identifiers.
    /// Any expression, alias, function call, qualified name, or `table.*` yields nil.
    private static func parseProjection(_ text: String) -> ParsedProjection? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == "*" { return .all }
        // Disallow anything that isn't a clean comma list of identifiers.
        guard !trimmed.contains("("), !trimmed.contains("*") else { return nil }
        var names: [String] = []
        for part in trimmed.split(separator: ",", omittingEmptySubsequences: false) {
            let token = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { return nil }
            // Reject aliases (`col AS x` / `col x`), qualified (`t.col`), operators, quotes we won't
            // round-trip. A bare identifier is letters/digits/underscore only, or a double-quoted /
            // backtick-quoted identifier with no interior separators.
            guard let name = bareIdentifier(token) else { return nil }
            guard !aggregateFunctions.contains(name.lowercased()) else { return nil }
            names.append(name)
        }
        return names.isEmpty ? nil : .columns(names)
    }

    /// A single unqualified column identifier, unquoted, or nil if the token has an alias, qualifier,
    /// operator, expression, or embedded whitespace.
    private static func bareIdentifier(_ token: String) -> String? {
        // Quoted identifier: "..." or `...` with no interior quote of the same kind.
        if token.hasPrefix("\""), token.hasSuffix("\""), token.count >= 2 {
            let inner = String(token.dropFirst().dropLast())
            return inner.contains("\"") || inner.isEmpty ? nil : inner
        }
        if token.hasPrefix("`"), token.hasSuffix("`"), token.count >= 2 {
            let inner = String(token.dropFirst().dropLast())
            return inner.contains("`") || inner.isEmpty ? nil : inner
        }
        // Bare identifier: [A-Za-z_][A-Za-z0-9_]*, no dot (qualifier), no whitespace (alias).
        guard let first = token.first, first.isLetter || first == "_" else { return nil }
        for ch in token where !isIdentChar(ch) { return nil }
        return token
    }

    /// Strip surrounding quotes/backticks from a table identifier so it matches the catalog name.
    private static func normalizeIdentifier(_ token: String) -> String? {
        bareIdentifier(token)
    }

    private static func isIdentChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }

    /// The set of whole words in `text` (identifier runs), used for keyword rejection.
    private static func tokenizeWords(_ text: String) -> Set<String> {
        var words: Set<String> = []
        var current = ""
        for ch in text {
            if isIdentChar(ch) {
                current.append(ch)
            } else if !current.isEmpty {
                words.insert(current)
                current = ""
            }
        }
        if !current.isEmpty { words.insert(current) }
        return words
    }
}

/// A results grid resolved as editable: the table, its primary-key columns, and the result columns
/// (all mapping 1:1 to real table columns). The engine dialect is attached separately by the caller.
public struct EditableResolution: Sendable, Hashable {
    public let table: String
    public let primaryKey: [String]
    public let resultColumns: [String]
    public init(table: String, primaryKey: [String], resultColumns: [String]) {
        self.table = table
        self.primaryKey = primaryKey
        self.resultColumns = resultColumns
    }
}

/// The pure reconciliation behind editable detection, split out so it can be unit-tested without the
/// app or a live driver. Given a parsed single-table SELECT, the table's real columns, and the result
/// grid's column names, decide whether the grid is editable. Every guard must pass; any failure → nil
/// (read-only). Conservative by design — a false positive would let an edit hit the wrong rows.
public enum SQLEditableResolver {
    public static func resolve(
        parsed: ParsedSelect,
        tableColumns: [ColumnInfo],
        resultColumns: [String]
    ) -> EditableResolution? {
        guard !tableColumns.isEmpty, !resultColumns.isEmpty else { return nil }
        let tableColumnNames = Set(tableColumns.map(\.name))
        let primaryKey = tableColumns.filter(\.isPrimaryKey).map(\.name)
        guard !primaryKey.isEmpty else { return nil }

        // Duplicate result column names would make write-by-name ambiguous.
        guard Set(resultColumns).count == resultColumns.count else { return nil }
        // Every result column must be a real column of this table.
        guard resultColumns.allSatisfy({ tableColumnNames.contains($0) }) else { return nil }
        // For a named projection, the parsed names must equal the result columns exactly.
        if case .columns(let named) = parsed.projection, named != resultColumns { return nil }
        // Every PK column must be visible in the result so each row can be UPDATE-d by its key.
        guard primaryKey.allSatisfy({ resultColumns.contains($0) }) else { return nil }

        return EditableResolution(table: parsed.table, primaryKey: primaryKey, resultColumns: resultColumns)
    }
}

/// Builds parameterized UPDATE statements for staged cell edits. The core guarantee: cell values are
/// NEVER put into the SQL string — they leave only as the ordered `params` array, which the driver
/// binds natively. Identifiers (table/column names) come from the DB catalog and are quoted per
/// dialect. A pure function so it can be asserted headlessly (placeholder count == params count).
public enum SQLUpdateBuilder {
    /// A built statement: the SQL text (placeholders only, no literals) and the value params in the
    /// exact order the placeholders appear (SET values first, then WHERE key values).
    public struct Statement: Sendable, Hashable {
        public let sql: String
        public let params: [SQLValue]
        public init(sql: String, params: [SQLValue]) {
            self.sql = sql
            self.params = params
        }
    }

    /// An error the builder raises rather than emit an unsafe/invalid statement.
    public enum BuildError: Error, Equatable {
        case noChanges
        case noKey
    }

    /// Build `UPDATE <table> SET c1=?,c2=? WHERE k1=? AND k2=?` for `dialect`.
    /// - `changes`: the columns being written, each with its new value (order preserved).
    /// - `keys`: the primary-key columns identifying the row, each with its value (order preserved).
    /// Placeholders are numbered per dialect; `params` = changes' values ++ keys' values.
    public static func build(
        table: String,
        changes: [(column: String, value: SQLValue)],
        keys: [(column: String, value: SQLValue)],
        dialect: SQLDialect
    ) throws -> Statement {
        guard !changes.isEmpty else { throw BuildError.noChanges }
        guard !keys.isEmpty else { throw BuildError.noKey }

        var placeholderIndex = 0
        func nextPlaceholder() -> String {
            placeholderIndex += 1
            return dialect.placeholder(placeholderIndex)
        }

        let setClause =
            changes
            .map { "\(dialect.quoteIdentifier($0.column)) = \(nextPlaceholder())" }
            .joined(separator: ", ")
        let whereClause =
            keys
            .map { "\(dialect.quoteIdentifier($0.column)) = \(nextPlaceholder())" }
            .joined(separator: " AND ")

        let sql = "UPDATE \(dialect.quoteIdentifier(table)) SET \(setClause) WHERE \(whereClause)"
        let params = changes.map(\.value) + keys.map(\.value)
        return Statement(sql: sql, params: params)
    }
}
