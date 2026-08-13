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
    func run(_ sql: String) async throws -> QueryResult
    func close() async
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
