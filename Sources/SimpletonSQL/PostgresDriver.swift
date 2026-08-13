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

    public func run(_ sql: String) async throws -> QueryResult {
        guard let connection else { throw SQLDriverError.notConnected }
        do {
            let seq = try await connection.query(PostgresQuery(unsafeSQL: sql), logger: logger)
            let pgRows = try await seq.collect()
            guard let first = pgRows.first else { return .status(affected: 0, message: "OK") }
            let columns = first.map { Column(name: $0.columnName) }
            let rows = pgRows.map { row in row.map { Self.value($0) } }
            return .rows(columns: columns, rows: rows)
        } catch {
            throw SQLDriverError.queryFailed("\(error)")
        }
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
                out.append(
                    ColumnInfo(
                        name: (try? cells[0].decode(String.self)) ?? "",
                        type: (try? cells[1].decode(String.self)) ?? "",
                        nullable: ((try? cells[2].decode(String.self)) ?? "").uppercased() == "YES",
                        isPrimaryKey: false))
            }
            return out
        } catch {
            throw SQLDriverError.queryFailed("\(error)")
        }
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
