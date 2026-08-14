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

    // Generic cell → SQLValue. MySQLData renders any type as a string; SQL NULL surfaces via its
    // description. (MVP note: values are text-typed for the grid; refine typing in a later slice.)
    private static func value(_ row: MySQLRow, _ name: String) -> SQLValue {
        guard let data = row.column(name) else { return .null }
        if let s = data.string { return .text(s) }
        return .text(data.description)
    }
}
