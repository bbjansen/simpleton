// Sources/SimpletonSQL/MySQLDriver.swift
import Foundation
import Logging
import MySQLNIO
import NIOCore
import NIOPosix
import SimpletonCore

/// MySQL driver over MySQLNIO. That library exposes only `EventLoopFuture` (no native async), so we
/// bridge each call with `.get()`. `@unchecked Sendable`: `connection` is set once in `connect()`.
public final class MySQLDriver: SQLDriver, @unchecked Sendable {
    private let host: String
    private let port: Int
    private let username: String
    private let database: String
    private let password: String?
    private let useTLS: Bool
    private let logger = Logger(label: "com.simpleton.sql.mysql")
    private var connection: MySQLConnection?

    public init(connection c: Connection, secret: ConnectionSecret?) throws {
        self.host = c.host ?? "127.0.0.1"
        self.port = c.port ?? 3306
        self.username = c.username ?? ""
        self.database = c.params["database"] ?? ""
        self.password = secret?.password
        self.useTLS = c.params["useTLS"] == "true"
    }

    public func connect() async throws {
        do {
            let address = try SocketAddress.makeAddressResolvingHost(host, port: port)
            connection = try await MySQLConnection.connect(
                to: address, username: username, database: database, password: password,
                tlsConfiguration: useTLS ? .makeClientConfiguration() : nil,
                logger: logger, on: SQLEventLoop.shared.any()
            ).get()
        } catch {
            throw SQLDriverError.connectionFailed("\(error)")
        }
    }

    public func close() async {
        _ = try? await connection?.close().get()
        connection = nil
    }

    public var dialect: SQLDialect { .mysql }

    public func run(_ sql: String) async throws -> QueryResult {
        try await execute(sql, [])
    }

    public func execute(_ sql: String, _ params: [SQLValue]) async throws -> QueryResult {
        guard let connection else { throw SQLDriverError.notConnected }
        do {
            // Binds are sent as `[MySQLData]` on MySQLNIO's prepared-statement path; when non-empty,
            // the driver uses `?` placeholders and NEVER splices values into `sql`.
            let binds = params.map(Self.bind)
            var affected: UInt64 = 0
            let rows = try await connection.query(sql, binds, onMetadata: { affected = $0.affectedRows }).get()
            guard let first = rows.first else {
                return .status(affected: Int(affected), message: "OK")
            }
            let names = first.columnDefinitions.map { $0.name }
            let columns = names.map { Column(name: $0) }
            let out = rows.map { row in names.map { Self.value(row, $0) } }
            return .rows(columns: columns, rows: out)
        } catch {
            throw SQLDriverError.queryFailed("\(error)")
        }
    }

    /// Map one `SQLValue` to a native `MySQLData` bind. Blobs bind as a raw binary buffer; SQL NULL
    /// is `MySQLData.null`. Values are typed here, not stringified into the SQL.
    private static func bind(_ value: SQLValue) -> MySQLData {
        switch value {
        case .null: return .null
        case .integer(let v): return MySQLData(int: Int(v))
        case .double(let v): return MySQLData(double: v)
        case .bool(let b): return MySQLData(bool: b)
        case .text(let s): return MySQLData(string: s)
        case .blob(let d):
            var buffer = ByteBufferAllocator().buffer(capacity: d.count)
            buffer.writeBytes(d)
            return MySQLData(type: .blob, format: .binary, buffer: buffer)
        }
    }

    public func databases() async throws -> [String] {
        guard case .rows(_, let rows) = try await run("SHOW DATABASES") else { return [] }
        return rows.compactMap { $0.first?.displayString }
    }

    /// Switch the live connection's default database with `USE`. The name (from `databases()`) is
    /// identifier-quoted, never interpolated as a value; afterwards `SHOW TABLES` and the
    /// `DATABASE()`-scoped introspection follow the new database with no reconnect. `USE` is sent over
    /// the **text protocol** (`simpleQuery`): it is not a preparable statement, so the driver's normal
    /// `run`/`execute` prepared-statement path cannot carry it.
    public func useDatabase(_ name: String) async throws -> Bool {
        guard let connection else { throw SQLDriverError.notConnected }
        do {
            _ = try await connection.simpleQuery("USE " + dialect.quoteIdentifier(name)).get()
            return true
        } catch {
            throw SQLDriverError.queryFailed("\(error)")
        }
    }

    public func tables(in database: String?) async throws -> [TableInfo] {
        guard case .rows(_, let rows) = try await run("SHOW FULL TABLES") else { return [] }
        return rows.compactMap { row in
            guard let name = row.first?.displayString else { return nil }
            let kind: TableKind =
                row.count > 1 && row[1].displayString.uppercased().contains("VIEW") ? .view : .table
            return TableInfo(name: name, kind: kind)
        }
    }

    public func columns(of table: String, in database: String?) async throws -> [ColumnInfo] {
        let escaped = table.replacingOccurrences(of: "`", with: "``")
        guard case .rows(_, let rows) = try await run("SHOW COLUMNS FROM `\(escaped)`") else { return [] }
        // SHOW COLUMNS: Field | Type | Null | Key | Default | Extra
        return rows.compactMap { row in
            guard row.count >= 4 else { return nil }
            return ColumnInfo(
                name: row[0].displayString, type: row[1].displayString,
                nullable: row[2].displayString.uppercased() == "YES",
                isPrimaryKey: row[3].displayString.uppercased() == "PRI")
        }
    }

    public func foreignKeys(of table: String, in database: String?) async throws -> [ForeignKeyInfo] {
        // KEY_COLUMN_USAGE lists every key column; FK rows are exactly those with a non-null
        // REFERENCED_TABLE_NAME. Scope to the connection's schema (DATABASE()) so a table of the same
        // name in another schema can't leak in. The table name is bound as a `?` parameter, never
        // spliced into the SQL. Rows come back in ordinal order so composite FKs stay grouped.
        let sql =
            "SELECT COLUMN_NAME, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME "
            + "FROM information_schema.KEY_COLUMN_USAGE "
            + "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? "
            + "AND REFERENCED_TABLE_NAME IS NOT NULL ORDER BY ORDINAL_POSITION"
        guard case .rows(_, let rows) = try await execute(sql, [.text(table)]) else { return [] }
        return rows.compactMap { row in
            guard row.count >= 3 else { return nil }
            let column = row[0].displayString
            let refTable = row[1].displayString
            let refColumn = row[2].displayString
            guard !column.isEmpty, !refTable.isEmpty, !refColumn.isEmpty else { return nil }
            return ForeignKeyInfo(column: column, referencedTable: refTable, referencedColumn: refColumn)
        }
    }

    // Generic cell → SQLValue. MySQLData renders any type as a string; SQL NULL surfaces via its
    // description. (MVP note: values are text-typed for the grid; refine typing in a later slice.)
    private static func value(_ row: MySQLRow, _ name: String) -> SQLValue {
        guard let data = row.column(name) else { return .null }
        if let s = data.string { return .text(s) }
        return .text(data.description)
    }
}
