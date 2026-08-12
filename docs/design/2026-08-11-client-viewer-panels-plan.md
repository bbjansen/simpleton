# Client-Viewer Panels — Phase 0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the shared substrate for the client-viewer panel suite — a generic connection/credential model and a reusable panel-chrome scaffold — validated by retrofitting Docker & Processes, and make the AI panel a special header-only feature.

**Architecture:** Add a backend-agnostic `Connection`/`ConnectionKind`/`ConnectionSecret` model + `ConnectionStore` actor + Keychain-backed `CredentialStore` to `SimpletonCore` (additive; the SSH `Bookmark` system is untouched). Extract the header/refresh/timer/empty-state boilerplate shared by tool panels into `ClientPanelScaffold`, then retrofit `DockerPanelView` and `ProcessesPanelView` onto it. Remove the AI panel's redundant activity-bar entry so it is opened only via the header button/menu/palette, and collapse the now-empty right rail.

**Tech Stack:** Swift 6 / Swift Package Manager (no Xcode), AppKit + SwiftUI-in-`NSHostingView`, `Security.framework` (Keychain), the no-Xcode `CoreChecks` executable test runner.

**Spec:** `docs/design/2026-08-11-client-viewer-panels.md`

## Global Constraints

- Build with `swift build`; run checks with `swift run CoreChecks`. XCTest/swift-testing are unavailable on this machine — all unit checks go through the `CoreChecks` runner.
- Codable models use the project's **tolerant `decodeIfPresent`** convention: every field missing from an older JSON file falls back to a default, never a decode failure.
- The SSH `Bookmark`, `BookmarkStore`, and `KeychainManager` (service `com.simpleton.ssh`) are **left untouched**. The new model is additive and independent.
- The new Keychain service is **`com.simpleton.connection`** (distinct from SSH's).
- Code must pass `swift format lint --recursive --parallel --strict Sources Tests` (the CI lint gate). When in doubt, run `swift format --in-place --recursive Sources Tests` before committing.
- Commit messages are conventional (`feat:`, `refactor:`, `test:`, `docs:`) with **no co-author trailer and no mention of Claude / AI agents**.
- **Non-goals this phase:** the backend `ClientProvider` data seam (designed with SQL in Phase 1) and any external-plugin runtime. Do not build them.
- `Tests/CoreChecks` is a directory glob in `Package.swift` — new `.swift` files there need **no** `Package.swift` change.

---

## File Structure

**Create**
- `Sources/SimpletonCore/Models/Connection.swift` — `ConnectionKind`, `Connection`, `ConnectionSecret` value types.
- `Sources/SimpletonCore/Core/ConnectionStore.swift` — `ConnectionStore` actor + `ConnectionFile` envelope + `.simpletonConnectionsChanged` notification name.
- `Sources/SimpletonCore/Core/CredentialStore.swift` — `CredentialStore` (Keychain, service `com.simpleton.connection`).
- `Sources/Simpleton/Panels/ClientPanelScaffold.swift` — `ClientAvailability` enum + `ClientPanelScaffold<Content>` view.
- `Tests/CoreChecks/ConnectionChecks.swift` — `runConnectionChecks` (sync) + `runConnectionStoreChecks` (async).

**Modify**
- `Tests/CoreChecks/main.swift` — register the two new check suites.
- `Sources/Simpleton/Panels/DockerPanelView.swift` — wrap in `ClientPanelScaffold`, delete duplicated chrome.
- `Sources/Simpleton/Panels/ProcessesPanelView.swift` — wrap in `ClientPanelScaffold`, delete duplicated chrome.
- `Sources/Simpleton/Panels/PanelProfile.swift:83-111` — drop `"ai-chat"` from every default profile's `rightPanelIDs`; set Developer's `rightActivePanelID` to `nil`.
- `Sources/Simpleton/TabContainerController.swift:436-463` (+ `updatePanels`) — capture the right-bar width constraint and collapse/hide the right rail when its side has no panels.

**Untouched (explicitly):** `Bookmark.swift`, `BookmarkStore.swift`, `KeychainManager.swift`, all AI conversation/`rebindAIChat` logic, `HeaderBarView.swift`, `MenuBarBuilder.swift`, the command-palette AI action.

---

## Task 1: Connection model (`Connection`, `ConnectionKind`, `ConnectionSecret`)

**Files:**
- Create: `Sources/SimpletonCore/Models/Connection.swift`
- Create: `Tests/CoreChecks/ConnectionChecks.swift`
- Modify: `Tests/CoreChecks/main.swift`

**Interfaces:**
- Produces: `Connection` (struct, `Codable, Identifiable, Equatable, Sendable`; `id: UUID`, `name: String`, `kind: ConnectionKind`, `host: String?`, `port: Int?`, `username: String?`, `params: [String:String]`, `tags: [String]`, `pinned: Bool`, `createdAt: Date`, `updatedAt: Date`; memberwise init with defaults + tolerant `init(from:)`). `ConnectionKind` (`String` enum, `Codable, CaseIterable, Sendable`; cases `.postgres .mysql .sqlite .amqp .s3 .ftp .sftp .ssh`; `displayName`, `icon`, `defaultPort: Int?`, `requiresCredentials: Bool`). `ConnectionSecret` (struct, `Codable, Equatable, Sendable`; optional `password/accessKey/secretKey/token/passphrase`). `func runConnectionChecks(_ t: TestRunner)`.

- [ ] **Step 1: Write the model file**

Create `Sources/SimpletonCore/Models/Connection.swift`:

```swift
// Sources/SimpletonCore/Models/Connection.swift
import Foundation

/// The kind of service a `Connection` points at. Drives the panel's icon, default port, and
/// whether credentials are required. `.ssh` is reserved for a future migration of the SSH bookmark
/// system onto this generic model; it is unused in Phase 0.
public enum ConnectionKind: String, Codable, CaseIterable, Sendable {
    case postgres, mysql, sqlite, amqp, s3, ftp, sftp, ssh

    public var displayName: String {
        switch self {
        case .postgres: return "PostgreSQL"
        case .mysql: return "MySQL"
        case .sqlite: return "SQLite"
        case .amqp: return "RabbitMQ"
        case .s3: return "S3"
        case .ftp: return "FTP"
        case .sftp: return "SFTP"
        case .ssh: return "SSH"
        }
    }

    /// SF Symbol name for the connection's icon.
    public var icon: String {
        switch self {
        case .postgres, .mysql, .sqlite: return "cylinder.split.1x2"
        case .amqp: return "arrow.left.arrow.right"
        case .s3: return "externaldrive.connected.to.line.below"
        case .ftp, .sftp: return "folder.badge.gearshape"
        case .ssh: return "terminal"
        }
    }

    /// The conventional default port, or nil for file-based kinds (SQLite).
    public var defaultPort: Int? {
        switch self {
        case .postgres: return 5432
        case .mysql: return 3306
        case .amqp: return 5672
        case .s3: return 443
        case .ftp: return 21
        case .sftp, .ssh: return 22
        case .sqlite: return nil
        }
    }

    /// Whether this kind needs stored credentials. SQLite is a local file → no credentials.
    public var requiresCredentials: Bool { self != .sqlite }
}

/// A saved, backend-agnostic connection to a service surfaced by a client-viewer panel. Shared
/// substrate for the DB / MQ / object-storage / file-transfer clients; the SSH `Bookmark` system is
/// separate and untouched. Secrets are NOT stored here — they live in `CredentialStore`, keyed by `id`.
public struct Connection: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: ConnectionKind
    public var host: String?
    public var port: Int?
    public var username: String?
    /// Kind-specific extra fields (e.g. "database", S3 "region"/"bucket"/"endpoint", "useTLS").
    public var params: [String: String]
    public var tags: [String]
    public var pinned: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        kind: ConnectionKind,
        host: String? = nil,
        port: Int? = nil,
        username: String? = nil,
        params: [String: String] = [:],
        tags: [String] = [],
        pinned: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.host = host
        self.port = port
        self.username = username
        self.params = params
        self.tags = tags
        self.pinned = pinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Tolerant decoding: any key missing from an older connections.json falls back to a default,
    /// so adding fields never drops a user's existing connections (matches the project convention).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        kind = try c.decodeIfPresent(ConnectionKind.self, forKey: .kind) ?? .postgres
        host = try c.decodeIfPresent(String.self, forKey: .host)
        port = try c.decodeIfPresent(Int.self, forKey: .port)
        username = try c.decodeIfPresent(String.self, forKey: .username)
        params = try c.decodeIfPresent([String: String].self, forKey: .params) ?? [:]
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

/// Secret material for a `Connection`, stored in the Keychain by `CredentialStore` (never in
/// connections.json). Several optional fields because different kinds need different secrets
/// (e.g. S3 needs an access key + secret key; a database needs a password).
public struct ConnectionSecret: Codable, Equatable, Sendable {
    public var password: String?
    public var accessKey: String?
    public var secretKey: String?
    public var token: String?
    public var passphrase: String?

    public init(
        password: String? = nil,
        accessKey: String? = nil,
        secretKey: String? = nil,
        token: String? = nil,
        passphrase: String? = nil
    ) {
        self.password = password
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.token = token
        self.passphrase = passphrase
    }
}
```

- [ ] **Step 2: Write the model checks (model + kind + secret only)**

Create `Tests/CoreChecks/ConnectionChecks.swift`:

```swift
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
```

- [ ] **Step 3: Register the suite in the runner**

In `Tests/CoreChecks/main.swift`, add to the **Models (synchronous)** group (e.g. right after `runWorkspaceChecks(runner)`):

```swift
runConnectionChecks(runner)
```

- [ ] **Step 4: Run the checks — verify they pass**

Run: `swift run CoreChecks`
Expected: build succeeds and the summary line reads `✓ CoreChecks: all N checks passed` (N increased by the four new suites' assertions). If it fails to build because `runConnectionChecks` is unknown, confirm the file is under `Tests/CoreChecks/`.

- [ ] **Step 5: Lint + commit**

```bash
swift format lint --recursive --parallel --strict Sources Tests || swift format --in-place --recursive Sources Tests
git add Sources/SimpletonCore/Models/Connection.swift Tests/CoreChecks/ConnectionChecks.swift Tests/CoreChecks/main.swift
git commit -m "feat(connections): add generic Connection model + kinds + secret"
```

---

## Task 2: `ConnectionStore` actor + change notification

**Files:**
- Create: `Sources/SimpletonCore/Core/ConnectionStore.swift`
- Modify: `Tests/CoreChecks/ConnectionChecks.swift` (add async store suite)
- Modify: `Tests/CoreChecks/main.swift` (register async suite)

**Interfaces:**
- Consumes: `Connection`, `ConnectionKind` (Task 1); `AtomicFileWriter.readJSON`/`writeJSON` (existing in `SimpletonCore`).
- Produces: `ConnectionStore` (`actor`; `init(directory: URL)`; `func load() throws`; `func add(_:) throws`, `update(_:) throws`, `delete(id:) throws`; `func all() -> [Connection]`, `byKind(_:) -> [Connection]`, `pinned() -> [Connection]`, `connection(for:) -> Connection?`, `search(query:) -> [Connection]`, `flush() throws`). `ConnectionFile` (`Codable`; `version: Int`, `connections: [Connection]`). `Notification.Name.simpletonConnectionsChanged`. `func runConnectionStoreChecks(_ t: TestRunner) async`.

- [ ] **Step 1: Write the store file**

Create `Sources/SimpletonCore/Core/ConnectionStore.swift`:

```swift
// Sources/SimpletonCore/Core/ConnectionStore.swift
import Foundation

public extension Notification.Name {
    /// Posted on the main queue after connections change, so UI can refresh.
    static let simpletonConnectionsChanged = Notification.Name("simpletonConnectionsChanged")
}

/// Persistent, actor-isolated store of `Connection`s, saved as JSON to `connections.json` in the
/// support directory. Mirrors `BookmarkStore` but for the generic client-viewer connections; the two
/// are independent. Secrets are not stored here (see `CredentialStore`).
public actor ConnectionStore {

    private let directory: URL
    private var connections: [UUID: Connection] = [:]
    private var loaded = false

    public init(directory: URL) {
        self.directory = directory
    }

    nonisolated private func postConnectionsChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .simpletonConnectionsChanged, object: nil)
        }
    }

    public func load() throws {
        let file = directory.appendingPathComponent("connections.json")
        if FileManager.default.fileExists(atPath: file.path) {
            let decoded = try AtomicFileWriter.readJSON(ConnectionFile.self, from: file)
            connections = Dictionary(uniqueKeysWithValues: decoded.connections.map { ($0.id, $0) })
        }
        loaded = true
    }

    private func ensureLoaded() throws {
        if !loaded { try load() }
    }

    public func add(_ connection: Connection) throws {
        try ensureLoaded()
        connections[connection.id] = connection
        try save()
        postConnectionsChanged()
    }

    public func update(_ connection: Connection) throws {
        try ensureLoaded()
        guard connections[connection.id] != nil else { return }
        var updated = connection
        updated.updatedAt = Date()
        connections[connection.id] = updated
        try save()
        postConnectionsChanged()
    }

    public func delete(id: UUID) throws {
        try ensureLoaded()
        connections.removeValue(forKey: id)
        try save()
        postConnectionsChanged()
    }

    public func all() -> [Connection] {
        try? ensureLoaded()
        return Array(connections.values).sorted { $0.name < $1.name }
    }

    public func byKind(_ kind: ConnectionKind) -> [Connection] {
        try? ensureLoaded()
        return connections.values.filter { $0.kind == kind }.sorted { $0.name < $1.name }
    }

    public func pinned() -> [Connection] {
        try? ensureLoaded()
        return connections.values.filter(\.pinned).sorted { $0.name < $1.name }
    }

    public func connection(for id: UUID) -> Connection? {
        try? ensureLoaded()
        return connections[id]
    }

    public func search(query: String) -> [Connection] {
        try? ensureLoaded()
        let q = query.lowercased()
        guard !q.isEmpty else { return all() }
        return connections.values
            .filter {
                $0.name.lowercased().contains(q)
                    || ($0.host?.lowercased().contains(q) ?? false)
                    || $0.tags.contains { $0.lowercased().contains(q) }
            }
            .sorted { $0.name < $1.name }
    }

    public func flush() throws {
        try save()
    }

    private func save() throws {
        let file = ConnectionFile(connections: Array(connections.values))
        try AtomicFileWriter.writeJSON(file, to: directory.appendingPathComponent("connections.json"))
    }
}

/// On-disk envelope for connections.json (versioned for forward migration).
public struct ConnectionFile: Codable {
    public let version: Int
    public var connections: [Connection]

    public init(version: Int = 1, connections: [Connection]) {
        self.version = version
        self.connections = connections
    }
}
```

- [ ] **Step 2: Add the async store checks**

Append to `Tests/CoreChecks/ConnectionChecks.swift`:

```swift
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
```

- [ ] **Step 3: Register the async suite**

In `Tests/CoreChecks/main.swift`, add to the **Core (async — actor-backed stores)** group (e.g. after `await runBookmarkStoreChecks(runner)`):

```swift
await runConnectionStoreChecks(runner)
```

- [ ] **Step 4: Run the checks — verify they pass**

Run: `swift run CoreChecks`
Expected: `✓ CoreChecks: all N checks passed`, including the four `ConnectionStore …` suites and the notification assertion firing `within 2s`.

- [ ] **Step 5: Lint + commit**

```bash
swift format lint --recursive --parallel --strict Sources Tests || swift format --in-place --recursive Sources Tests
git add Sources/SimpletonCore/Core/ConnectionStore.swift Tests/CoreChecks/ConnectionChecks.swift Tests/CoreChecks/main.swift
git commit -m "feat(connections): add ConnectionStore actor with change notification"
```

---

## Task 3: `CredentialStore` (Keychain)

**Files:**
- Create: `Sources/SimpletonCore/Core/CredentialStore.swift`
- Modify: `Tests/CoreChecks/ConnectionChecks.swift` (add guarded credential checks, called from `runConnectionChecks`)

**Interfaces:**
- Consumes: `ConnectionSecret` (Task 1).
- Produces: `CredentialStore` (`enum`, namespace of statics; `@discardableResult static func store(_ secret: ConnectionSecret, for id: UUID) -> Bool`; `static func secret(for id: UUID) -> ConnectionSecret?`; `@discardableResult static func delete(for id: UUID) -> Bool`; `static func has(id: UUID) -> Bool`).

- [ ] **Step 1: Write the credential store file**

Create `Sources/SimpletonCore/Core/CredentialStore.swift`:

```swift
// Sources/SimpletonCore/Core/CredentialStore.swift
import Foundation
import Security

/// Keychain-backed store for `ConnectionSecret`s, keyed by a `Connection`'s id. Generalizes the
/// SSH-only `KeychainManager` (service "com.simpleton.ssh") to a separate service for the generic
/// client-viewer connections. The secret is JSON-encoded and stored as the item's data blob.
public enum CredentialStore {

    private static let service = "com.simpleton.connection"

    @discardableResult
    public static func store(_ secret: ConnectionSecret, for id: UUID) -> Bool {
        guard let data = try? JSONEncoder().encode(secret) else { return false }
        let account = id.uuidString

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        // Upsert: update in place if present, else add — mirrors KeychainManager's robustness
        // against errSecInvalidOwnerEdit from items created by an earlier build's signature.
        let updateStatus = SecItemUpdate(
            query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            addQuery[kSecAttrLabel as String] = "Simpleton Connection: \(account)"
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    public static func secret(for id: UUID) -> ConnectionSecret? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(ConnectionSecret.self, from: data)
    }

    @discardableResult
    public static func delete(for id: UUID) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    public static func has(id: UUID) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }
}
```

- [ ] **Step 2: Add the guarded credential checks**

In `Tests/CoreChecks/ConnectionChecks.swift`, add this private function and **call it at the end of `runConnectionChecks`** (add the line `runCredentialStoreChecks(t)` as the last statement inside `runConnectionChecks`):

```swift
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
```

- [ ] **Step 3: Run the checks — verify they pass**

Run: `swift run CoreChecks`
Expected: `✓ CoreChecks: all N checks passed`. On a machine with Keychain access the `CredentialStore …` suite runs; on a locked-down runner it prints `… CredentialStore checks skipped (Keychain unavailable in this runner)` and the run still passes. Either outcome is a pass — never a failure.

- [ ] **Step 4: Lint + commit**

```bash
swift format lint --recursive --parallel --strict Sources Tests || swift format --in-place --recursive Sources Tests
git add Sources/SimpletonCore/Core/CredentialStore.swift Tests/CoreChecks/ConnectionChecks.swift
git commit -m "feat(connections): add Keychain-backed CredentialStore"
```

---

## Task 4: `ClientPanelScaffold` + `ClientAvailability`

**Files:**
- Create: `Sources/Simpleton/Panels/ClientPanelScaffold.swift`

**Interfaces:**
- Consumes: `DT` design tokens, `ThemeSettings.shared`, `ThemedDivider`, `PanelEmptyStateView(icon:title:message:actionLabel:action:)` (all existing in the `Simpleton` target).
- Produces: `ClientAvailability` (enum: `.loading`; `.ready`; `.unavailable(icon: String, title: String, message: String, actionLabel: String? = nil, action: (() -> Void)? = nil)`). `ClientPanelScaffold<Content: View>` (`init(title: String, availability: ClientAvailability, autoRefresh: TimeInterval?, onRefresh: @escaping () async -> Void, @ViewBuilder content: @escaping () -> Content)`).

Design notes for the implementer:
- The scaffold owns the chrome (header + refresh button + `ThemedDivider`), the auto-refresh `Timer`, and the switch over `availability`. The consumer owns its data `@State`, computes `availability`, and supplies `content` + an `onRefresh` closure that mutates that state.
- The **manual** refresh button shows a spinner while its tap is in flight (`isRefreshing`); **auto** (timer) refreshes are silent so a fast 3–5s poll doesn't flash the header.
- The scaffold fires `onRefresh` once on appear and then every `autoRefresh` seconds (skip the timer when `autoRefresh == nil`), and invalidates the timer on disappear.

- [ ] **Step 1: Write the scaffold file**

Create `Sources/Simpleton/Panels/ClientPanelScaffold.swift`:

```swift
// Sources/Simpleton/Panels/ClientPanelScaffold.swift
import SwiftUI

/// Availability of a client panel's backing service, driving what the scaffold shows in its body.
enum ClientAvailability {
    /// First load in progress — show a spinner.
    case loading
    /// Service reachable — show the panel's own `content`.
    case ready
    /// Service unavailable (missing CLI, not running, unreachable) — show an empty state with an
    /// optional action button. Fields map straight onto `PanelEmptyStateView`.
    case unavailable(icon: String, title: String, message: String, actionLabel: String? = nil, action: (() -> Void)? = nil)
}

/// Shared chrome for tool/client panels: an uppercase title, a refresh button (spinner while a
/// manual refresh runs), a `ThemedDivider`, and a body that switches on `availability`. Owns the
/// auto-refresh timer so consumers only supply their data + an `onRefresh` closure. Extracted from
/// the original Docker/Processes panels so every client panel shares one look and lifecycle.
struct ClientPanelScaffold<Content: View>: View {
    let title: String
    let availability: ClientAvailability
    let autoRefresh: TimeInterval?
    let onRefresh: () async -> Void
    @ViewBuilder let content: () -> Content

    @ObservedObject private var themeSettings = ThemeSettings.shared
    @State private var timer: Timer?
    @State private var isRefreshing = false

    init(
        title: String,
        availability: ClientAvailability,
        autoRefresh: TimeInterval?,
        onRefresh: @escaping () async -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.availability = availability
        self.autoRefresh = autoRefresh
        self.onRefresh = onRefresh
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ThemedDivider()
            body(for: availability)
        }
        .onAppear {
            Task { await onRefresh() }
            if let interval = autoRefresh {
                timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                    Task { @MainActor in await onRefresh() }
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.5)
                .foregroundColor(DT.textPrimary)
            Spacer()
            Button {
                Task {
                    isRefreshing = true
                    await onRefresh()
                    isRefreshing = false
                }
            } label: {
                if isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise").foregroundColor(DT.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func body(for availability: ClientAvailability) -> some View {
        switch availability {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            content()
        case .unavailable(let icon, let title, let message, let actionLabel, let action):
            PanelEmptyStateView(
                icon: icon, title: title, message: message, actionLabel: actionLabel, action: action)
        }
    }
}
```

- [ ] **Step 2: Build — verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!` with no errors. (No unit test — the scaffold is validated by its two consumers in Tasks 5–6.)

- [ ] **Step 3: Lint + commit**

```bash
swift format lint --recursive --parallel --strict Sources Tests || swift format --in-place --recursive Sources Tests
git add Sources/Simpleton/Panels/ClientPanelScaffold.swift
git commit -m "feat(panels): add ClientPanelScaffold shared chrome for tool panels"
```

---

## Task 5: Retrofit `DockerPanelView` onto the scaffold

**Files:**
- Modify: `Sources/Simpleton/Panels/DockerPanelView.swift`

**Interfaces:**
- Consumes: `ClientPanelScaffold`, `ClientAvailability` (Task 4).

Goal: the panel keeps its `Process`-based data fetch, its `DockerPanelState` model, and its `dockerList(_:)` row rendering, but delegates all chrome to the scaffold. Delete the panel's own header `HStack`, its `ThemedDivider()`, its `.onAppear`/`.onDisappear` timer wiring, and the top-level `VStack` that held them.

- [ ] **Step 1: Map the existing state onto `availability` + wrap in the scaffold**

Replace the panel's `body` so it returns a single `ClientPanelScaffold`. Map `DockerPanelState` to availability like this (keep the existing `refresh()` method and `@State private var state` exactly as they are; keep `dockerList(_:)` unchanged):

```swift
var body: some View {
    ClientPanelScaffold(
        title: "DOCKER",
        availability: availability,
        autoRefresh: 5,
        onRefresh: { await refresh() }
    ) {
        if case .loaded(let containers) = state {
            dockerList(containers)
        }
    }
}

private var availability: ClientAvailability {
    switch state {
    case .loading:
        return .loading
    case .notInstalled:
        return .unavailable(
            icon: "shippingbox",
            title: "Docker not installed",
            message: "Install Docker Desktop to use this panel.",
            actionLabel: "Get Docker",
            action: { NSWorkspace.shared.open(URL(string: "https://www.docker.com/products/docker-desktop/")!) })
    case .notRunning:
        return .unavailable(
            icon: "shippingbox",
            title: "Docker not running",
            message: "Start Docker Desktop to see your containers.",
            actionLabel: "Open Docker Desktop",
            action: { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Docker.app")) })
    case .loaded:
        return .ready
    }
}
```

- [ ] **Step 2: Delete the now-duplicated chrome**

Remove from `DockerPanelView`: the old header `HStack` (the `Text("DOCKER") … Button … arrow.clockwise`), the standalone `ThemedDivider()`, the outer `VStack(spacing: 0)` that wrapped header/divider/switch, and the `.onAppear { … Timer.scheduledTimer … }` / `.onDisappear { timer?.invalidate() … }` block. Delete the now-unused `@State private var timer: Timer?`. Keep `@State private var state`, `refresh()`, `dockerList(_:)`, `containerActions(_:)`, and the `@ObservedObject … ThemeSettings.shared` may be removed (the scaffold observes theme) — remove it only if the compiler flags it as unused; otherwise leave it.

- [ ] **Step 3: Build — verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!` — no "unused variable `timer`" warning (means the old timer state was removed).

- [ ] **Step 4: Runtime check**

Run: `swift run CoreChecks` (must stay green — no regression), then launch the app and confirm the Docker panel: shows the header "DOCKER" + refresh button, renders containers (or the "Docker not installed"/"not running" empty state with its action button), and auto-refreshes ~every 5s. Tapping refresh shows a brief spinner in the header.

- [ ] **Step 5: Lint + commit**

```bash
swift format lint --recursive --parallel --strict Sources Tests || swift format --in-place --recursive Sources Tests
git add Sources/Simpleton/Panels/DockerPanelView.swift
git commit -m "refactor(panels): retrofit Docker panel onto ClientPanelScaffold"
```

---

## Task 6: Retrofit `ProcessesPanelView` onto the scaffold

**Files:**
- Modify: `Sources/Simpleton/Panels/ProcessesPanelView.swift`

**Interfaces:**
- Consumes: `ClientPanelScaffold`, `ClientAvailability` (Task 4).

Goal: same as Task 5 but simpler — `ps` is always available, so availability is always `.ready`; the "No processes" empty state stays inside `content` (it is a content-level empty, not an availability failure). Keep `@State private var processes`, `load()`, and the `List` row rendering unchanged.

- [ ] **Step 1: Wrap the body in the scaffold**

Replace the panel's `body`:

```swift
var body: some View {
    ClientPanelScaffold(
        title: "PROCESSES",
        availability: .ready,
        autoRefresh: 3,
        onRefresh: { await load() }
    ) {
        if processes.isEmpty {
            PanelEmptyStateView(
                icon: "cpu",
                title: "No processes",
                message: "Running processes will appear here.")
        } else {
            List(processes) { proc in
                processRow(proc)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}
```

If the row content is currently inline inside the `List(processes) { proc in … }`, extract it into a `@ViewBuilder private func processRow(_ proc: ProcessEntry) -> some View` holding the existing `HStack` (command + PID/CPU/MEM + kill button) verbatim, so the `body` above compiles as written.

- [ ] **Step 2: Delete the now-duplicated chrome**

Remove from `ProcessesPanelView`: the old header `HStack` (`Text("PROCESSES") … Button … arrow.clockwise`), the standalone `ThemedDivider()`, the outer `VStack(spacing: 0)`, the `.onAppear { … Timer.scheduledTimer(withTimeInterval: 3 …) }` / `.onDisappear { … }` block, and the now-unused `@State private var timer: Timer?`. Handle the `@ObservedObject … ThemeSettings.shared` as in Task 5 (remove only if flagged unused).

- [ ] **Step 3: Build — verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!` with no unused-`timer` warning.

- [ ] **Step 4: Runtime check**

Run: `swift run CoreChecks` (stays green), then launch the app and confirm the Processes panel: header "PROCESSES" + refresh, lists processes sorted by CPU, kill button works, auto-refreshes ~every 3s, manual refresh shows a brief header spinner.

- [ ] **Step 5: Lint + commit**

```bash
swift format lint --recursive --parallel --strict Sources Tests || swift format --in-place --recursive Sources Tests
git add Sources/Simpleton/Panels/ProcessesPanelView.swift
git commit -m "refactor(panels): retrofit Processes panel onto ClientPanelScaffold"
```

---

## Task 7: AI panel cleanup + collapse empty right rail

**Files:**
- Modify: `Sources/Simpleton/Panels/PanelProfile.swift:83-111`
- Modify: `Sources/Simpleton/TabContainerController.swift` (`mountActivityBars` at `436-463`, `updatePanels(for:)` at `498-537`, and a new stored property)

**Interfaces:**
- Consumes: existing `PanelProfile` default profiles; the `$activeProfile` Combine sink that already calls `updatePanels(for:)`.

Background (verified): `togglePanel(id:on:)` sets `rightActivePanelID = id` **unconditionally**, and `updatePanels(for:)` mounts `profile.rightActivePanelID` via `panelRegistry.makeController` **without** requiring membership in `rightPanelIDs`. So the header AI button (→ `.simpletonToggleAIChat` → `togglePanel(id: "ai-chat", on: .right)`) still mounts the AI panel after we remove `"ai-chat"` from `rightPanelIDs`. The activity-bar rail, however, renders a button for **every** id in `rightPanelIDs` — that is the redundant entry to remove. Removing it empties the right rail for all default profiles, so we also collapse the fixed 40px rail when its side has no panels.

- [ ] **Step 1: Remove `ai-chat` from the default profiles**

In `Sources/Simpleton/Panels/PanelProfile.swift`, in `defaultProfiles`, change each profile's `rightPanelIDs: ["ai-chat"]` to `rightPanelIDs: []`, and change the **Developer** profile's `rightActivePanelID: "ai-chat"` to `rightActivePanelID: nil` (General and DevOps are already `nil`). Result:

```swift
// General
leftPanelIDs: ["connections", "history", "file-browser"],
rightPanelIDs: [],
leftActivePanelID: "connections",
rightActivePanelID: nil
// Developer
leftPanelIDs: [
    "connections", "snippets", "notes", "history", "environment", "file-browser", "processes",
    "ssh-tunnels",
],
rightPanelIDs: [],
leftActivePanelID: "connections",
rightActivePanelID: nil
// DevOps
leftPanelIDs: ["connections", "notes", "ssh-tunnels", "processes", "git", "docker"],
rightPanelIDs: [],
leftActivePanelID: "connections",
rightActivePanelID: nil
```

Leave the `PanelProfile.PanelID.aiChat` constant and the `ai-chat` panel **registration** intact — the panel still exists and is mounted on demand by the header toggle.

- [ ] **Step 2: Capture the right-bar width constraint**

In `TabContainerController.swift`, add a stored property near the other bar-host properties (`leftBarHost`/`rightBarHost`):

```swift
private var rightBarWidthConstraint: NSLayoutConstraint?
```

In `mountActivityBars(in:registry:)`, pull the right bar's width constraint out of the `activate` array so it can be stored and later adjusted. Replace the inline `rightBar.widthAnchor.constraint(equalToConstant: 40)` inside `NSLayoutConstraint.activate([…])` with a named constraint activated alongside the rest:

```swift
let rightWidth = rightBar.widthAnchor.constraint(equalToConstant: 40)
rightBarWidthConstraint = rightWidth
NSLayoutConstraint.activate([
    // Left bar
    leftBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
    leftBar.topAnchor.constraint(equalTo: container.topAnchor),
    leftBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    leftBar.widthAnchor.constraint(equalToConstant: 40),
    // Right bar
    rightBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    rightBar.topAnchor.constraint(equalTo: container.topAnchor),
    rightBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    rightWidth,
    // Content split between bars
    split.leadingAnchor.constraint(equalTo: leftBar.trailingAnchor),
    split.trailingAnchor.constraint(equalTo: rightBar.leadingAnchor),
    split.topAnchor.constraint(equalTo: container.topAnchor),
    split.bottomAnchor.constraint(equalTo: container.bottomAnchor),
])
```

At the very end of `mountActivityBars(in:registry:)`, seed the initial visibility from the active profile:

```swift
updateRightBarVisibility(for: registry.activeProfile)
```

- [ ] **Step 3: Add the visibility updater and drive it from profile changes**

Add this method to `TabContainerController`:

```swift
/// Collapse the right activity-bar rail to zero width and hide it when its side has no panels
/// (e.g. after the AI panel moved to a header-only button). It reappears automatically once a
/// right-side panel is added to the profile.
private func updateRightBarVisibility(for profile: PanelProfile) {
    let isEmpty = profile.rightPanelIDs.isEmpty
    rightBarWidthConstraint?.constant = isEmpty ? 0 : 40
    rightBarHost?.isHidden = isEmpty
}
```

Call it from `updatePanels(for:)` (which the `$activeProfile` sink already invokes on every change, including the initial value). Add, near the top of `updatePanels(for:)`:

```swift
updateRightBarVisibility(for: profile)
```

- [ ] **Step 4: Build — verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`.

- [ ] **Step 5: Runtime check (the interactive behavior)**

Run: `swift run CoreChecks` (stays green), then launch the app and confirm:
1. The right activity-bar rail shows **no** AI (sparkles) icon and no empty 40px strip — the terminal extends to the trailing edge.
2. The top-right header **sparkles** button opens the AI panel on the right; the rail appears only while the panel is open, and the panel closes again on a second tap.
3. **⇧⌘A** (menu bar "AI → AI Chat") and the **command palette "AI: Chat"** both still toggle the AI panel.
4. Switching profiles (General/Developer/DevOps) never leaves a stray empty right strip.

- [ ] **Step 6: Lint + commit**

```bash
swift format lint --recursive --parallel --strict Sources Tests || swift format --in-place --recursive Sources Tests
git add Sources/Simpleton/Panels/PanelProfile.swift Sources/Simpleton/TabContainerController.swift
git commit -m "refactor(panels): make AI panel header-only and collapse the empty right rail"
```

---

## Task 8: Final verification

**Files:** none (verification only).

- [ ] **Step 1: Full build**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`.

- [ ] **Step 2: Full check suite**

Run: `swift run CoreChecks`
Expected: `✓ CoreChecks: all N checks passed` (the `Connection…` / `ConnectionStore…` suites present; `CredentialStore…` either ran or printed the skip line).

- [ ] **Step 3: Lint gate**

Run: `swift format lint --recursive --parallel --strict Sources Tests`
Expected: exit 0, no output.

- [ ] **Step 4: Headless e2e smoke (existing harness)**

Run: `SIMPLETON_WORKSPACE_E2E=1 scripts/e2e/workspace-e2e.sh` (or the repo's documented e2e entry point).
Expected: the run logs `SIMP-WSE2E RESULT PASS` — confirms the app still launches and drives a workspace headlessly after the panel/rail changes.

---

## Self-Review

**Spec coverage**
- §5 Component 1 (connection/credential model) → Tasks 1–3. `Connection`/`ConnectionKind`/`ConnectionSecret`, `ConnectionStore` (+ `.simpletonConnectionsChanged`), `CredentialStore` (service `com.simpleton.connection`) all present.
- §5 Component 2 (`ClientPanelScaffold` + Docker/Processes retrofit) → Tasks 4–6.
- §5 Component 3 (AI header-only, per-tab, de-duplicated from rail) → Task 7. Per-tab `TabConversation`/`rebindAIChat` untouched; header/menu/palette paths preserved.
- §8 Testing (CoreChecks for model/store/credential; scaffold + AI via build/e2e) → Tasks 1–3 checks + Task 8 e2e.
- §9 File structure matches Tasks 1–7; `Bookmark`/`BookmarkStore`/`KeychainManager` untouched as required.

**Placeholder scan:** no TBD/TODO; every code step carries full source; runtime/interactive checks are explicit steps, not "add error handling".

**Type consistency:** `ClientAvailability.unavailable(icon:title:message:actionLabel:action:)` matches `PanelEmptyStateView`'s `(icon:title:message:actionLabel:action:)`. `ClientPanelScaffold(title:availability:autoRefresh:onRefresh:content:)` used identically in Tasks 5–6. `ConnectionStore` method names (`all/byKind/pinned/connection(for:)/search/flush`) match between Task 2 source and its checks. `CredentialStore.store/secret/delete/has` match between Task 3 source and its checks. `runConnectionChecks` (sync, calls `runCredentialStoreChecks`) and `runConnectionStoreChecks` (async) match their `main.swift` registrations.
