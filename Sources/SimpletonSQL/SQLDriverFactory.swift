// Sources/SimpletonSQL/SQLDriverFactory.swift
import Foundation
import SimpletonCore

/// Builds the right `SQLDriver` for a `Connection`. Postgres/MySQL cases are added in later tasks.
public enum SQLDriverFactory {
    public static func make(_ connection: Connection, secret: ConnectionSecret?) throws -> SQLDriver {
        switch connection.kind {
        case .sqlite:
            return SQLiteDriver(path: connection.params["path"] ?? "")
        case .postgres:
            return try PostgresDriver(connection: connection, secret: secret)
        case .mysql:
            return try MySQLDriver(connection: connection, secret: secret)
        default:
            throw SQLDriverError.unsupported("\(connection.kind.rawValue) is not a SQL connection")
        }
    }
}
