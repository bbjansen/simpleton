// Sources/SimpletonSFTP/SFTPBackendFactory.swift
import Foundation
import SimpletonCore

/// Builds the right `SFTPBackend` for a `Connection`. Only `.sftp` is supported; every other kind
/// throws `.unsupported`. (Classic FTP is deprecated and intentionally not implemented.)
public enum SFTPBackendFactory {
    public static func make(_ connection: Connection, secret: ConnectionSecret?) throws -> SFTPBackend {
        switch connection.kind {
        case .sftp:
            return CitadelSFTPBackend(connection: connection, secret: secret)
        default:
            throw SFTPError.unsupported("\(connection.kind.rawValue) is not an SFTP connection")
        }
    }
}
