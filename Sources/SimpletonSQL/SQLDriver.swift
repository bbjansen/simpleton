// Sources/SimpletonSQL/SQLDriver.swift
import Foundation

/// The backend-agnostic interface every SQL engine implements. All I/O is async and runs off the
/// main actor; drivers map every failure to `SQLDriverError` so no raw engine error escapes.
public protocol SQLDriver: AnyObject, Sendable {
    func connect() async throws
    /// Postgres: databases; MySQL: schemas; SQLite: attached databases ("main", …).
    func databases() async throws -> [String]
    func tables(in database: String?) async throws -> [TableInfo]
    func columns(of table: String, in database: String?) async throws -> [ColumnInfo]
    /// The foreign keys declared on `table`: each maps one local column to a (referencedTable,
    /// referencedColumn) pair. Read from the engine's catalog (SQLite `PRAGMA foreign_key_list`,
    /// Postgres/MySQL `information_schema`), so it reflects the real constraints, not a heuristic.
    /// Used to offer a "Go to <referencedTable>" jump from an FK cell. Empty when the table has none.
    func foreignKeys(of table: String, in database: String?) async throws -> [ForeignKeyInfo]
    /// Run a raw statement (the query editor). The text is executed verbatim — it is the user's
    /// own SQL — so this path is *not* used for programmatic UPDATEs built from cell values.
    func run(_ sql: String) async throws -> QueryResult
    /// Run a statement with values bound **natively** by the engine (never string-interpolated into
    /// the SQL). `sql` must use this driver's `dialect` placeholder syntax; `params` supplies one
    /// value per placeholder, in order. This is the only path used to write edited cells, so cell
    /// values can never reach the SQL text. Drivers map every `SQLValue` case to a native bind.
    func execute(_ sql: String, _ params: [SQLValue]) async throws -> QueryResult
    func close() async
    /// The placeholder dialect for `execute`, so callers build `UPDATE … WHERE …` with the correct
    /// placeholder syntax and identifier quoting for this engine.
    var dialect: SQLDialect { get }
}

/// Per-engine SQL surface that the parameterized-write path needs: how placeholders are written and
/// how identifiers are quoted. Kept tiny and value-typed so the UPDATE builder is pure and testable.
public enum SQLDialect: String, Sendable, Hashable {
    /// SQLite / MySQL: positional `?` placeholders; identifiers quoted per style below.
    case sqlite
    case mysql
    /// PostgreSQL: numbered `$1`, `$2`, … placeholders.
    case postgres

    /// The placeholder token for the 1-based parameter at `index` (`?` for sqlite/mysql, `$n` for pg).
    public func placeholder(_ index: Int) -> String {
        switch self {
        case .sqlite, .mysql: return "?"
        case .postgres: return "$\(index)"
        }
    }

    /// Quote a table/column identifier for this engine, escaping the quote char by doubling it.
    /// MySQL uses backticks; SQLite and Postgres use double quotes. This never carries a *value* —
    /// only schema identifiers (table/column names), which come from the DB catalog, not user input.
    public func quoteIdentifier(_ raw: String) -> String {
        switch self {
        case .mysql:
            return "`" + raw.replacingOccurrences(of: "`", with: "``") + "`"
        case .sqlite, .postgres:
            return "\"" + raw.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
    }
}

public enum TableKind: String, Sendable, Hashable { case table, view }

public struct TableInfo: Sendable, Hashable {
    public let name: String
    public let kind: TableKind
    public init(name: String, kind: TableKind) {
        self.name = name
        self.kind = kind
    }
}

public struct ColumnInfo: Sendable, Hashable {
    public let name: String
    public let type: String
    public let nullable: Bool
    public let isPrimaryKey: Bool
    public init(name: String, type: String, nullable: Bool, isPrimaryKey: Bool) {
        self.name = name
        self.type = type
        self.nullable = nullable
        self.isPrimaryKey = isPrimaryKey
    }
}

/// One foreign-key edge declared on a table: the local `column` references `referencedColumn` in
/// `referencedTable`. Value-typed + `Sendable` so it crosses the driver boundary and can be unit
/// tested headlessly. A composite FK (multiple columns) surfaces as several `ForeignKeyInfo` rows.
public struct ForeignKeyInfo: Sendable, Hashable {
    /// The local (owning-table) column that holds the reference.
    public let column: String
    /// The table the reference points at.
    public let referencedTable: String
    /// The column in `referencedTable` the value matches (its key, usually the primary key).
    public let referencedColumn: String
    public init(column: String, referencedTable: String, referencedColumn: String) {
        self.column = column
        self.referencedTable = referencedTable
        self.referencedColumn = referencedColumn
    }
}

/// Pure matching of a result grid's columns to a table's foreign keys, split out so the FK-navigation
/// logic is unit-tested without a live driver. Given the result column names (grid order) and the
/// table's declared foreign keys, produce, for each result column that IS an FK, the target it jumps
/// to. Only single-column FKs are offered (a composite FK can't be navigated from one cell alone).
public enum SQLForeignKeyMatcher {
    /// One navigable FK cell: the result-column index (grid position) plus where it points. The value
    /// to filter by is read from the clicked cell at query time — it is never part of this mapping.
    public struct Match: Sendable, Hashable {
        /// Index into the result columns (grid column position) of the FK column.
        public let columnIndex: Int
        /// The referenced table to open.
        public let referencedTable: String
        /// The referenced column to filter (`WHERE referencedColumn = ?`).
        public let referencedColumn: String
        public init(columnIndex: Int, referencedTable: String, referencedColumn: String) {
            self.columnIndex = columnIndex
            self.referencedTable = referencedTable
            self.referencedColumn = referencedColumn
        }
    }

    /// Build the per-column FK jumps for a result. `resultColumns` is the grid's column names in order;
    /// `foreignKeys` is the owning table's declared FKs. A result column matches an FK by name
    /// (case-insensitive, to tolerate catalog casing differences). Composite FKs — where the same
    /// local column pair references multiple target columns — are excluded so a single cell never
    /// produces an ambiguous or partial filter. Result columns are matched in grid order; the first FK
    /// declared for a column wins if a column somehow appears in two single-column FKs.
    public static func matches(resultColumns: [String], foreignKeys: [ForeignKeyInfo]) -> [Match] {
        guard !resultColumns.isEmpty, !foreignKeys.isEmpty else { return [] }
        // Count how many FK edges touch each local column; a column in a composite FK (count > 1) is
        // not single-column-navigable and is skipped.
        var edgeCount: [String: Int] = [:]
        for fk in foreignKeys { edgeCount[fk.column.lowercased(), default: 0] += 1 }
        // First single-column FK per local column (lowercased key), so lookup is deterministic.
        var byColumn: [String: ForeignKeyInfo] = [:]
        for fk in foreignKeys {
            let key = fk.column.lowercased()
            guard edgeCount[key] == 1, byColumn[key] == nil else { continue }
            byColumn[key] = fk
        }
        var result: [Match] = []
        for (index, name) in resultColumns.enumerated() {
            guard let fk = byColumn[name.lowercased()] else { continue }
            result.append(
                Match(
                    columnIndex: index, referencedTable: fk.referencedTable,
                    referencedColumn: fk.referencedColumn))
        }
        return result
    }
}

/// A cell value, normalized across engines for a generic (unknown-columns) results grid.
public enum SQLValue: Sendable, Hashable {
    case null
    case integer(Int64)
    case double(Double)
    case text(String)
    case bool(Bool)
    case blob(Data)

    /// Whether this is SQL NULL — used to gate actions (e.g. FK navigation) that need a concrete key.
    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    public var displayString: String {
        switch self {
        case .null: return "NULL"
        case .integer(let v): return String(v)
        case .double(let v): return String(v)
        case .text(let v): return v
        case .bool(let v): return v ? "true" : "false"
        case .blob(let d): return "<\(d.count) bytes>"
        }
    }
}

public struct Column: Sendable, Hashable {
    public let name: String
    public let declaredType: String?
    public init(name: String, declaredType: String? = nil) {
        self.name = name
        self.declaredType = declaredType
    }
}

public enum QueryResult: Sendable {
    /// A row-returning statement (SELECT / PRAGMA / SHOW …).
    case rows(columns: [Column], rows: [[SQLValue]])
    /// A non-row statement (INSERT/UPDATE/DDL) — affected-row count + a status message.
    case status(affected: Int, message: String)
}

public enum SQLDriverError: Error, Sendable, Equatable {
    case connectionFailed(String)
    case queryFailed(String)
    case notConnected
    case unsupported(String)
}
