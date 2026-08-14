// Sources/SimpletonSQL/PostgresDriver.swift
import Foundation
import Logging
import NIOSSL
import PostgresNIO
import SimpletonCore

/// PostgreSQL driver over PostgresNIO's native async API. Holds one connection per instance.
/// `@unchecked Sendable`: `connection` is assigned once in `connect()` before any use.
public final class PostgresDriver: SQLDriver, @unchecked Sendable {
    private let config: PostgresConnection.Configuration
    private let logger = Logger(label: "com.simpleton.sql.postgres")
    private var connection: PostgresConnection?

    public init(connection c: Connection, secret: ConnectionSecret?) throws {
        let tls: PostgresConnection.Configuration.TLS =
            c.params["useTLS"] == "true"
            ? .require(try NIOSSLContext(configuration: .makeClientConfiguration()))
            : .disable
        self.config = PostgresConnection.Configuration(
            host: c.host ?? "localhost",
            port: c.port ?? 5432,
            username: c.username ?? "",
            password: secret?.password,
            database: c.params["database"],
            tls: tls)
    }

    public func connect() async throws {
        do {
            connection = try await PostgresConnection.connect(
                on: SQLEventLoop.shared.any(), configuration: config, id: 1, logger: logger)
        } catch {
            throw SQLDriverError.connectionFailed("\(error)")
        }
    }

    public func close() async {
        try? await connection?.close()
        connection = nil
    }

    public var dialect: SQLDialect { .postgres }

    public func run(_ sql: String) async throws -> QueryResult {
        guard let connection else { throw SQLDriverError.notConnected }
        do {
            let seq = try await connection.query(PostgresQuery(unsafeSQL: sql), logger: logger)
            return try await Self.materialize(seq)
        } catch {
            throw SQLDriverError.queryFailed("\(error)")
        }
    }

    public func execute(_ sql: String, _ params: [SQLValue]) async throws -> QueryResult {
        guard let connection else { throw SQLDriverError.notConnected }
        do {
            // Values are appended to PostgresBindings and sent over the extended-query protocol as
            // typed binary parameters — they are NEVER concatenated into `sql`. The placeholders in
            // `sql` are `$1..$n` (see SQLDialect.postgres).
            var binds = PostgresBindings(capacity: params.count)
            for value in params { Self.bind(value, into: &binds) }
            let seq = try await connection.query(PostgresQuery(unsafeSQL: sql, binds: binds), logger: logger)
            return try await Self.materialize(seq)
        } catch {
            throw SQLDriverError.queryFailed("\(error)")
        }
    }

    /// Append one `SQLValue` to `binds` using PostgresNIO's native encoders (typed binary binds).
    private static func bind(_ value: SQLValue, into binds: inout PostgresBindings) {
        switch value {
        case .null: binds.appendNull()
        case .integer(let v): binds.append(v)
        case .double(let v): binds.append(v)
        case .bool(let b): binds.append(b)
        case .text(let s): binds.append(s)
        case .blob(let d): binds.append(ByteBuffer(bytes: d))
        }
    }

    /// Collect a Postgres row sequence into a generic `QueryResult`. A statement that returns no
    /// rows (UPDATE/DDL) surfaces as `.status`; the row count is reported by callers via re-query.
    private static func materialize(_ seq: PostgresRowSequence) async throws -> QueryResult {
        let pgRows = try await seq.collect()
        guard let first = pgRows.first else { return .status(affected: 0, message: "OK") }
        let columns = first.map { Column(name: $0.columnName) }
        let rows = pgRows.map { row in row.map { Self.value($0) } }
        return .rows(columns: columns, rows: rows)
    }

    public func databases() async throws -> [String] {
        guard
            case .rows(_, let rows) = try await run(
                "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname")
        else { return [] }
        return rows.compactMap { $0.first?.displayString }
    }

    public func tables(in database: String?) async throws -> [TableInfo] {
        guard
            case .rows(_, let rows) = try await run(
                "SELECT table_name, table_type FROM information_schema.tables "
                    + "WHERE table_schema = 'public' ORDER BY table_name")
        else { return [] }
        return rows.compactMap { row in
            guard row.count >= 2 else { return nil }
            let kind: TableKind = row[1].displayString.uppercased().contains("VIEW") ? .view : .table
            return TableInfo(name: row[0].displayString, kind: kind)
        }
    }

    public func columns(of table: String, in database: String?) async throws -> [ColumnInfo] {
        guard let connection else { throw SQLDriverError.notConnected }
        do {
            let primaryKeys = try await primaryKeyColumns(of: table, on: connection)
            // `table` is bound as a parameter ($1) via PostgresQuery string interpolation — NOT raw
            // SQL — so no manual escaping and no injection surface (contrast `run`'s unsafeSQL path,
            // which intentionally executes the user's own IDE queries).
            let seq = try await connection.query(
                """
                SELECT column_name, data_type, is_nullable FROM information_schema.columns \
                WHERE table_name = \(table) ORDER BY ordinal_position
                """, logger: logger)
            var out: [ColumnInfo] = []
            for try await row in seq {
                let cells = Array(row)
                guard cells.count >= 3 else { continue }
                let name = (try? cells[0].decode(String.self)) ?? ""
                out.append(
                    ColumnInfo(
                        name: name,
                        type: (try? cells[1].decode(String.self)) ?? "",
                        nullable: ((try? cells[2].decode(String.self)) ?? "").uppercased() == "YES",
                        isPrimaryKey: primaryKeys.contains(name)))
            }
            return out
        } catch {
            throw SQLDriverError.queryFailed("\(error)")
        }
    }

    public func foreignKeys(of table: String, in database: String?) async throws -> [ForeignKeyInfo] {
        guard let connection else { throw SQLDriverError.notConnected }
        do {
            // Join the three information_schema views that describe a foreign-key constraint: the
            // owning column (key_column_usage), the referenced column (constraint_column_usage), and
            // the constraint metadata (referential_constraints ties the two together by name).
            // `table` is bound as `$1` (a typed parameter), never interpolated into SQL.
            let seq = try await connection.query(
                """
                SELECT kcu.column_name, ccu.table_name AS referenced_table, \
                ccu.column_name AS referenced_column \
                FROM information_schema.table_constraints tc \
                JOIN information_schema.key_column_usage kcu \
                ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema \
                JOIN information_schema.constraint_column_usage ccu \
                ON tc.constraint_name = ccu.constraint_name AND tc.table_schema = ccu.table_schema \
                WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = 'public' \
                AND tc.table_name = \(table) ORDER BY kcu.ordinal_position
                """, logger: logger)
            var out: [ForeignKeyInfo] = []
            for try await row in seq {
                let cells = Array(row)
                guard cells.count >= 3 else { continue }
                let column = (try? cells[0].decode(String.self)) ?? ""
                let refTable = (try? cells[1].decode(String.self)) ?? ""
                let refColumn = (try? cells[2].decode(String.self)) ?? ""
                guard !column.isEmpty, !refTable.isEmpty, !refColumn.isEmpty else { continue }
                out.append(
                    ForeignKeyInfo(column: column, referencedTable: refTable, referencedColumn: refColumn))
            }
            return out
        } catch {
            throw SQLDriverError.queryFailed("\(error)")
        }
    }

    /// The primary-key column names for `table` (public schema), read from the system catalogs.
    /// `table` is bound as `$1` (a typed parameter), never interpolated into SQL. Editability hinges
    /// on this being correct, so it comes from `pg_index.indisprimary`, not a heuristic.
    private func primaryKeyColumns(of table: String, on connection: PostgresConnection) async throws -> Set<String> {
        let seq = try await connection.query(
            """
            SELECT a.attname FROM pg_index i \
            JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey) \
            WHERE i.indrelid = \(table)::regclass AND i.indisprimary
            """, logger: logger)
        var keys: Set<String> = []
        for try await row in seq {
            if let name = try? row.decode(String.self) { keys.insert(name) }
        }
        return keys
    }

    // Generic cell → SQLValue. Common types decode precisely; anything else falls back to text.
    // (MVP note: primary-key flag and exotic types render as text; refine in a later slice.)
    private static func value(_ cell: PostgresCell) -> SQLValue {
        guard cell.bytes != nil else { return .null }
        switch cell.dataType {
        case .bool: return (try? cell.decode(Bool.self)).map(SQLValue.bool) ?? text(cell)
        case .int2, .int4, .int8: return (try? cell.decode(Int64.self)).map(SQLValue.integer) ?? text(cell)
        case .float4, .float8: return (try? cell.decode(Double.self)).map(SQLValue.double) ?? text(cell)
        default: return text(cell)
        }
    }
    private static func text(_ cell: PostgresCell) -> SQLValue {
        (try? cell.decode(String.self)).map(SQLValue.text) ?? .text("<\(cell.dataType)>")
    }
}
