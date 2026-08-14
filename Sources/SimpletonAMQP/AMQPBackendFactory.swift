// Sources/SimpletonAMQP/AMQPBackendFactory.swift
import Foundation
import SimpletonCore

/// Builds the right `AMQPManagementBackend` for a `Connection`. Only `.amqp` is supported today;
/// mirrors `SimpletonSQL`'s `SQLDriverFactory`.
public enum AMQPBackendFactory {
    public static func make(_ connection: Connection, secret: ConnectionSecret?) throws -> AMQPManagementBackend {
        switch connection.kind {
        case .amqp:
            return try RabbitMQManagementDriver(connection: connection, secret: secret)
        default:
            throw AMQPError.unsupported("\(connection.kind.rawValue) is not an AMQP connection")
        }
    }
}
