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

    runCredentialStoreChecks(t)
}

/// Keychain-backed; guarded because an unsigned `swift run CoreChecks` binary (or a headless CI
/// runner) often cannot access the Keychain. We probe first and skip cleanly if it's unavailable,
/// so these checks never produce a false CI failure.
private func runCredentialStoreChecks(_ t: TestRunner) {
    let probeID = UUID()
    let probeOK = CredentialStore.store(ConnectionSecret(password: "probe"), for: probeID)
    CredentialStore.delete(for: probeID)
    guard probeOK else {
        print("  … CredentialStore checks skipped (Keychain unavailable in this runner)")
        return
    }

    t.suite("CredentialStore store / retrieve / has / delete round-trip") {
        let id = UUID()
        defer { CredentialStore.delete(for: id) }
        let secret = ConnectionSecret(password: "hunter2", accessKey: "AKIA", secretKey: "shh")
        t.expect(CredentialStore.store(secret, for: id), "store succeeds")
        t.expect(CredentialStore.has(id: id), "has() true after store")
        t.expectEqual(CredentialStore.secret(for: id), secret, "retrieved secret matches")
        t.expect(CredentialStore.delete(for: id), "delete succeeds")
        t.expect(!CredentialStore.has(id: id), "has() false after delete")
        t.expect(CredentialStore.secret(for: id) == nil, "secret nil after delete")
    }
}

func runConnectionStoreChecks(_ t: TestRunner) async {
    func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("corechecks-conn-" + UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    await t.suite("ConnectionStore add / all / byKind / pinned") {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            let store = ConnectionStore(directory: dir)
            try await store.add(Connection(name: "pg", kind: .postgres, pinned: true))
            try await store.add(Connection(name: "my", kind: .mysql))
            try await store.add(Connection(name: "lite", kind: .sqlite))
            t.expectEqual(await store.all().count, 3, "three connections stored")
            t.expectEqual(await store.byKind(.postgres).count, 1, "one postgres connection")
            t.expectEqual(await store.pinned().count, 1, "one pinned connection")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    await t.suite("ConnectionStore update / delete / search") {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            let store = ConnectionStore(directory: dir)
            var c = Connection(name: "web-prod", kind: .postgres, host: "10.0.0.1")
            try await store.add(c)
            c.name = "web-prod-renamed"
            try await store.update(c)
            t.expectEqual(await store.connection(for: c.id)?.name, "web-prod-renamed", "renamed")
            t.expectEqual(await store.search(query: "10.0.0").count, 1, "search matches host")
            try await store.delete(id: c.id)
            t.expect(await store.all().isEmpty, "empty after delete")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    await t.suite("ConnectionStore persistence across instances") {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            let s1 = ConnectionStore(directory: dir)
            try await s1.add(Connection(name: "persisted", kind: .amqp))
            try await s1.flush()
            let s2 = ConnectionStore(directory: dir)
            try await s2.load()
            t.expectEqual(await s2.all().count, 1, "second instance loads persisted connection")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    await t.suite("ConnectionStore posts .simpletonConnectionsChanged on add") {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ConnectionStore(directory: dir)
        // The store posts on the main queue; observe on .main and race it against a 2s timeout.
        // Both the observer and the timeout run serially on the main queue, so a plain `done`
        // flag is safe and the continuation resumes exactly once.
        let fired = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            var done = false
            var obs: NSObjectProtocol?
            obs = NotificationCenter.default.addObserver(
                forName: .simpletonConnectionsChanged, object: nil, queue: .main
            ) { _ in
                guard !done else { return }
                done = true
                if let obs { NotificationCenter.default.removeObserver(obs) }
                cont.resume(returning: true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard !done else { return }
                done = true
                if let obs { NotificationCenter.default.removeObserver(obs) }
                cont.resume(returning: false)
            }
            Task { try? await store.add(Connection(name: "x", kind: .s3)) }
        }
        t.expect(fired, ".simpletonConnectionsChanged fired within 2s")
    }
}
