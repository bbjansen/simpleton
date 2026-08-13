// Sources/SimpletonS3/S3BackendFactory.swift
import Foundation
import SimpletonCore

/// Builds the right `S3Backend` for a `Connection`. Only `.s3` is supported; any other kind throws
/// `.unsupported`, mirroring `SQLDriverFactory`.
public enum S3BackendFactory {
    public static func make(_ connection: Connection, secret: ConnectionSecret?) throws -> S3Backend {
        switch connection.kind {
        case .s3:
            return SotoS3Backend(connection: connection, secret: secret)
        default:
            throw S3Error.unsupported("\(connection.kind.rawValue) is not an S3 connection")
        }
    }
}
