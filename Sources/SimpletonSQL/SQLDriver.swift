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

/// A cell value, normalized across engines for a generic (unknown-columns) results grid.
public enum SQLValue: Sendable, Hashable {
    case null
    case integer(Int64)
    case double(Double)
    case text(String)
    case bool(Bool)
    case blob(Data)

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
