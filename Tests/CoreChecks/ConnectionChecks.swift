// Tests/CoreChecks/ConnectionChecks.swift
import Foundation
import SimpletonCore

func runConnectionChecks(_ t: TestRunner) {
    t.suite("Connection.Codable round-trip preserves all fields") {
        let original = Connection(
            name: "prod-db", kind: .postgres, host: "db.example.com", port: 5432,
            username: "app", params: ["database": "app_prod", "useTLS": "true"],
            tags: ["prod", "db"], pinned: true)
        do {
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(Connection.self, from: data)
            t.expectEqual(decoded, original, "decoded connection equals original")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    t.suite("Connection tolerant decode — missing new fields fall back to defaults") {
        let json = #"{"id":"11111111-1111-1111-1111-111111111111","name":"legacy","kind":"mysql"}"#
        do {
            let decoded = try JSONDecoder().decode(Connection.self, from: Data(json.utf8))
            t.expectEqual(decoded.name, "legacy", "name decoded")
            t.expectEqual(decoded.kind, ConnectionKind.mysql, "kind decoded")
            t.expect(decoded.params.isEmpty, "params defaults to empty")
            t.expect(decoded.tags.isEmpty, "tags defaults to empty")
            t.expect(!decoded.pinned, "pinned defaults to false")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    t.suite("ConnectionKind helpers") {
        t.expectEqual(ConnectionKind.postgres.defaultPort, 5432, "postgres port")
        t.expectEqual(ConnectionKind.mysql.defaultPort, 3306, "mysql port")
        t.expectEqual(ConnectionKind.sqlite.defaultPort, nil, "sqlite has no port")
        t.expect(ConnectionKind.postgres.requiresCredentials, "postgres needs credentials")
        t.expect(!ConnectionKind.sqlite.requiresCredentials, "sqlite needs no credentials")
    }

    t.suite("ConnectionSecret.Codable round-trip") {
        let secret = ConnectionSecret(accessKey: "AKIA", secretKey: "s3cr3t", token: "tok")
        do {
            let data = try JSONEncoder().encode(secret)
            let decoded = try JSONDecoder().decode(ConnectionSecret.self, from: data)
            t.expectEqual(decoded, secret, "secret round-trips")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }
}
