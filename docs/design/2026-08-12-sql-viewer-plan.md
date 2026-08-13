# SQL Viewer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS SQL client panel (full query IDE) for SQLite, PostgreSQL, and MySQL, built on the Phase 0 client-viewer foundation.

**Architecture:** A new `SimpletonSQL` SPM library holds the pure data layer — the async `SQLDriver` seam, three drivers (SQLite via `libsqlite3`, Postgres via PostgresNIO, MySQL via MySQLNIO), result/schema models, a driver factory, and a shared NIO `EventLoopGroup` — keeping SwiftNIO out of `SimpletonCore`. The SQL panel UI lives in the app target, reuses `ClientPanelScaffold`, and talks only to `SimpletonSQL`.

**Tech Stack:** Swift 6 / SPM (no Xcode), AppKit + SwiftUI-in-`NSHostingController`, `libsqlite3` (system), PostgresNIO 1.33.1, MySQLNIO 1.9.1, the `CoreChecks` executable test runner.

**Spec:** `docs/design/2026-08-12-sql-viewer.md`

## Global Constraints

- Build with `swift build`; run checks with `swift run CoreChecks`; lint with `swift format lint --recursive --parallel --strict Sources Tests` (must exit 0). XCTest/swift-testing are unavailable — all unit checks go through `CoreChecks`.
- **Exact-version dependencies only** (no `from:`/ranges): `postgres-nio` **exact 1.33.1**, `mysql-nio` **exact 1.9.1**. Commit the updated `Package.resolved`.
- These drivers' manifests require a Swift 6.1+ toolchain to parse; local (6.3.3) and CI (`macos-15` + latest-stable Xcode) both satisfy it — **no CI workflow change needed**.
- Codable types use the tolerant `decodeIfPresent` convention (missing keys fall back to defaults, never a decode failure).
- Drivers run all I/O **off the main actor** and map every failure to `SQLDriverError` — no raw NIO/SQLite errors escape the driver boundary.
- `SimpletonSQL` must not be imported by `SimpletonCore` (NIO stays out of the core).
- Postgres/MySQL CoreChecks are **integration-gated**: probe a server via env var, and **skip cleanly with a printed note** when absent (mirroring the `CredentialStore` Keychain guard) so CI never fails for lack of a DB.
- Commit messages are conventional (`feat:`, `refactor:`, `test:`, `docs:`) with **no co-author trailer and no mention of Claude / AI agents**.
- **Out of scope:** the marketplace / licensing / payments layer; autocomplete; export; SSH-tunneled DB connections.

## Integration facts (verified against the current tree)

- Panels register **explicitly** in `Sources/Simpleton/AppDelegate.swift` (~lines 151–162: `panelRegistry.register(.docker)` etc.). Add `panelRegistry.register(.sql)` there.
- Panel definitions are `static let` on `extension PanelDefinition` in `Sources/Simpleton/Panels/BuiltInPanels.swift`.
- `PanelDefinition`: `id, name, icon, description, defaultSide: PanelSide, isBuiltIn: Bool, make: (PanelContext) -> NSViewController`.
- `PanelContext` exposes `appSupportDir: URL` (and `appConfig()`, `currentPane()`, `bookmarkStore`, …) but **no `ConnectionStore`** — the SQL panel creates its own `ConnectionStore(directory: context.appSupportDir)` (single consumer of `connections.json`; no cross-cutting change).
- `ClientPanelScaffold(title:availability:autoRefresh:onRefresh:content:)` with `ClientAvailability` = `.loading | .ready | .unavailable(icon:title:message:actionLabel:action:)`.
- Phase 0 APIs (in `SimpletonCore`): `Connection(id:name:kind:host:port:username:params:tags:pinned:…)`, `ConnectionKind` (`.postgres/.mysql/.sqlite/…`, `.defaultPort`, `.requiresCredentials`), `ConnectionStore` actor (`add/update/delete/all/byKind/pinned/connection(for:)/search/flush`), `CredentialStore` (`store(_:for:) / secret(for:) / delete(for:) / has(id:)`), `ConnectionSecret(password:accessKey:secretKey:token:passphrase:)`.

---

## File Structure

**Create**
- `Sources/SimpletonSQL/SQLDriver.swift` — `SQLDriver` protocol + models.
- `Sources/SimpletonSQL/SQLDriverFactory.swift` — kind → driver.
- `Sources/SimpletonSQL/SQLiteDriver.swift` — `libsqlite3` driver.
- `Sources/SimpletonSQL/SQLEventLoop.swift` — shared `EventLoopGroup` (Task 5).
- `Sources/SimpletonSQL/PostgresDriver.swift` (Task 5).
- `Sources/SimpletonSQL/MySQLDriver.swift` (Task 6).
- `Sources/SimpletonSQL/SQLQueryHistoryStore.swift` (Task 4).
- `Sources/Simpleton/Panels/SQL/SQLPanelModel.swift` — `@MainActor ObservableObject`.
- `Sources/Simpleton/Panels/SQL/SQLPanelView.swift` — IDE shell in `ClientPanelScaffold`.
- `Sources/Simpleton/Panels/SQL/SQLResultsGrid.swift`
- `Sources/Simpleton/Panels/SQL/SQLConnectionEditor.swift`
- `Sources/Simpleton/Panels/SQL/SQLSchemaBrowser.swift` (Task 4).
- `Tests/CoreChecks/SQLDriverChecks.swift`

**Modify**
- `Package.swift` — add the two packages + `SimpletonSQL` target; add `SimpletonSQL` to `Simpleton` and `CoreChecks` deps.
- `Sources/Simpleton/Panels/BuiltInPanels.swift` — `static let sql` definition.
- `Sources/Simpleton/Panels/PanelProfile.swift` — `PanelID.sql`; add to a default profile.
- `Sources/Simpleton/AppDelegate.swift` — `panelRegistry.register(.sql)`.
- `Tests/CoreChecks/main.swift` — register `runSQLDriverChecks`.

---

## Task 1: Dependencies + `SimpletonSQL` skeleton (seam + models)

**Files:**
- Modify: `Package.swift`
- Create: `Sources/SimpletonSQL/SQLDriver.swift`
- Test: `Tests/CoreChecks/SQLDriverChecks.swift` (model-only checks) + register in `Tests/CoreChecks/main.swift`

**Interfaces:**
- Produces: `SQLDriver` protocol; `TableInfo`/`TableKind`, `ColumnInfo`, `Column`, `SQLValue`, `QueryResult`, `SQLDriverError`; `func runSQLDriverChecks(_ t: TestRunner) async`.

- [ ] **Step 1: Add dependencies + the `SimpletonSQL` target**

In `Package.swift`, add to `dependencies:`:
```swift
        .package(url: "https://github.com/vapor/postgres-nio.git", exact: "1.33.1"),
        .package(url: "https://github.com/vapor/mysql-nio.git", exact: "1.9.1"),
```
Add a target (after `SimpletonCore`):
```swift
        .target(
            name: "SimpletonSQL",
            dependencies: [
                "SimpletonCore",
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "MySQLNIO", package: "mysql-nio"),
            ]
        ),
```
Add `"SimpletonSQL"` to the `Simpleton` executable target's `dependencies`, and to the `CoreChecks` target's `dependencies` (so checks can import it).

- [ ] **Step 2: Write the seam + models**

Create `Sources/SimpletonSQL/SQLDriver.swift`:
```swift
// Sources/SimpletonSQL/SQLDriver.swift
import Foundation

/// The backend-agnostic interface every SQL engine implements. All I/O is async and runs off the
/// main actor; drivers map every failure to `SQLDriverError` so no raw engine error escapes.
public protocol SQLDriver: AnyObject, Sendable {
    func connect() async throws
    /// Postgres: databases; MySQL: schemas; SQLite: attached databases ("main", …).
    func databases() async throws -> [String]
    func tables(in database: String?) async throws -> [TableInfo]
    func columns(of table: String, in database: String?) async throws -> [ColumnInfo]
    func run(_ sql: String) async throws -> QueryResult
    func close() async
}

public enum TableKind: String, Sendable, Hashable { case table, view }

public struct TableInfo: Sendable, Hashable {
    public let name: String
    public let kind: TableKind
    public init(name: String, kind: TableKind) { self.name = name; self.kind = kind }
}

public struct ColumnInfo: Sendable, Hashable {
    public let name: String
    public let type: String
    public let nullable: Bool
    public let isPrimaryKey: Bool
    public init(name: String, type: String, nullable: Bool, isPrimaryKey: Bool) {
        self.name = name; self.type = type; self.nullable = nullable; self.isPrimaryKey = isPrimaryKey
    }
}

/// A cell value, normalized across engines for a generic (unknown-columns) results grid.
public enum SQLValue: Sendable, Hashable {
    case null
    case integer(Int64)
    case double(Double)
    case text(String)
    case bool(Bool)
    case blob(Data)

    public var displayString: String {
        switch self {
        case .null: return "NULL"
        case .integer(let v): return String(v)
        case .double(let v): return String(v)
        case .text(let v): return v
        case .bool(let v): return v ? "true" : "false"
        case .blob(let d): return "<\(d.count) bytes>"
        }
    }
}

public struct Column: Sendable, Hashable {
    public let name: String
    public let declaredType: String?
    public init(name: String, declaredType: String? = nil) { self.name = name; self.declaredType = declaredType }
}

public enum QueryResult: Sendable {
    /// A row-returning statement (SELECT / PRAGMA / SHOW …).
    case rows(columns: [Column], rows: [[SQLValue]])
    /// A non-row statement (INSERT/UPDATE/DDL) — affected-row count + a status message.
    case status(affected: Int, message: String)
}

public enum SQLDriverError: Error, Sendable, Equatable {
    case connectionFailed(String)
    case queryFailed(String)
    case notConnected
    case unsupported(String)
}
```

- [ ] **Step 3: Write the model checks**

Create `Tests/CoreChecks/SQLDriverChecks.swift`:
```swift
// Tests/CoreChecks/SQLDriverChecks.swift
import Foundation
import SimpletonSQL

func runSQLDriverChecks(_ t: TestRunner) async {
    t.suite("SQLValue.displayString") {
        t.expectEqual(SQLValue.null.displayString, "NULL", "null")
        t.expectEqual(SQLValue.integer(42).displayString, "42", "integer")
        t.expectEqual(SQLValue.text("hi").displayString, "hi", "text")
        t.expectEqual(SQLValue.bool(true).displayString, "true", "bool")
        t.expectEqual(SQLValue.blob(Data([1, 2, 3])).displayString, "<3 bytes>", "blob")
    }

    t.suite("QueryResult shapes") {
        let rows = QueryResult.rows(columns: [Column(name: "id")], rows: [[.integer(1)]])
        if case .rows(let cols, let r) = rows {
            t.expectEqual(cols.count, 1, "one column")
            t.expectEqual(r.count, 1, "one row")
        } else {
            t.expect(false, "expected .rows")
        }
        if case .status(let n, _) = QueryResult.status(affected: 3, message: "OK") {
            t.expectEqual(n, 3, "affected count")
        } else {
            t.expect(false, "expected .status")
        }
    }
}
```
Register in `Tests/CoreChecks/main.swift` — add to the async group (after `await runConnectionStoreChecks(runner)`):
```swift
await runSQLDriverChecks(runner)
```

- [ ] **Step 4: Build + run checks**

Run: `swift build 2>&1 | tail -3` → `Build complete!` (resolves the NIO graph on first build).
Run: `swift run CoreChecks 2>&1 | tail -1` → `✓ CoreChecks: all N checks passed`.

- [ ] **Step 5: Lint + commit (include Package.resolved)**

```bash
swift format lint --recursive --parallel --strict Sources Tests || swift format --in-place --recursive Sources Tests
git add Package.swift Package.resolved Sources/SimpletonSQL/SQLDriver.swift Tests/CoreChecks/SQLDriverChecks.swift Tests/CoreChecks/main.swift
git commit -m "feat(sql): add SimpletonSQL target with SQLDriver seam and models"
```

---

## Task 2: `SQLiteDriver` + `SQLDriverFactory` + real SQLite checks

**Files:**
- Create: `Sources/SimpletonSQL/SQLiteDriver.swift`, `Sources/SimpletonSQL/SQLDriverFactory.swift`
- Modify: `Tests/CoreChecks/SQLDriverChecks.swift`

**Interfaces:**
- Consumes: `SQLDriver` + models (Task 1); `Connection`/`ConnectionKind`/`ConnectionSecret` (`SimpletonCore`).
- Produces: `SQLiteDriver(path:)`; `SQLDriverFactory.make(_ connection: Connection, secret: ConnectionSecret?) throws -> SQLDriver`.

- [ ] **Step 1: Write the SQLite driver**

Create `Sources/SimpletonSQL/SQLiteDriver.swift`:
```swift
// Sources/SimpletonSQL/SQLiteDriver.swift
import Foundation
import SQLite3

/// SQLite driver over the system `libsqlite3`. All C-API access is confined to a single serial
/// queue (hence `@unchecked Sendable`); the async protocol methods hop onto that queue.
public final class SQLiteDriver: SQLDriver, @unchecked Sendable {
    private let path: String
    private let queue = DispatchQueue(label: "com.simpleton.sql.sqlite")
    private var db: OpaquePointer?

    public init(path: String) { self.path = path }

    private func onQueue<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                do { cont.resume(returning: try work()) } catch { cont.resume(throwing: error) }
            }
        }
    }

    public func connect() async throws {
        try await onQueue {
            var handle: OpaquePointer?
            let rc = sqlite3_open_v2(
                self.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
            guard rc == SQLITE_OK, let handle else {
                let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unable to open \(self.path)"
                if let handle { sqlite3_close(handle) }
                throw SQLDriverError.connectionFailed(msg)
            }
            self.db = handle
        }
    }

    public func close() async {
        try? await onQueue {
            if let db = self.db { sqlite3_close(db); self.db = nil }
        }
    }

    public func run(_ sql: String) async throws -> QueryResult {
        try await onQueue { try self.query(sql) }
    }

    public func databases() async throws -> [String] {
        guard case .rows(_, let rows) = try await run("PRAGMA database_list") else { return [] }
        // PRAGMA database_list columns: seq | name | file — name is index 1.
        return rows.compactMap { $0.count > 1 ? $0[1].displayString : nil }
    }

    public func tables(in database: String?) async throws -> [TableInfo] {
        let result = try await run(
            "SELECT name, type FROM sqlite_master WHERE type IN ('table','view') ORDER BY name")
        guard case .rows(_, let rows) = result else { return [] }
        return rows.compactMap { row in
            guard row.count >= 2 else { return nil }
            let kind: TableKind = row[1].displayString == "view" ? .view : .table
            return TableInfo(name: row[0].displayString, kind: kind)
        }
    }

    public func columns(of table: String, in database: String?) async throws -> [ColumnInfo] {
        let escaped = table.replacingOccurrences(of: "\"", with: "\"\"")
        let result = try await run("PRAGMA table_info(\"\(escaped)\")")
        guard case .rows(_, let rows) = result else { return [] }
        // PRAGMA table_info columns: cid | name | type | notnull | dflt_value | pk
        return rows.compactMap { row in
            guard row.count >= 6 else { return nil }
            let notnull = row[3].displayString != "0"
            let pk = row[5].displayString != "0"
            return ColumnInfo(name: row[1].displayString, type: row[2].displayString, nullable: !notnull, isPrimaryKey: pk)
        }
    }

    // MARK: - core (queue-confined)

    private func query(_ sql: String) throws -> QueryResult {
        guard let db else { throw SQLDriverError.notConnected }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLDriverError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        let colCount = Int(sqlite3_column_count(stmt))
        if colCount == 0 {
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw SQLDriverError.queryFailed(String(cString: sqlite3_errmsg(db)))
            }
            return .status(affected: Int(sqlite3_changes(db)), message: "OK")
        }

        var columns: [Column] = []
        columns.reserveCapacity(colCount)
        for i in 0..<colCount {
            let name = String(cString: sqlite3_column_name(stmt, Int32(i)))
            let decl = sqlite3_column_decltype(stmt, Int32(i)).map { String(cString: $0) }
            columns.append(Column(name: name, declaredType: decl))
        }

        var out: [[SQLValue]] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else {
                throw SQLDriverError.queryFailed(String(cString: sqlite3_errmsg(db)))
            }
            var row: [SQLValue] = []
            row.reserveCapacity(colCount)
            for i in 0..<colCount { row.append(Self.cell(stmt, Int32(i))) }
            out.append(row)
        }
        return .rows(columns: columns, rows: out)
    }

    private static func cell(_ stmt: OpaquePointer?, _ i: Int32) -> SQLValue {
        switch sqlite3_column_type(stmt, i) {
        case SQLITE_NULL: return .null
        case SQLITE_INTEGER: return .integer(sqlite3_column_int64(stmt, i))
        case SQLITE_FLOAT: return .double(sqlite3_column_double(stmt, i))
        case SQLITE_BLOB:
            if let bytes = sqlite3_column_blob(stmt, i) {
                return .blob(Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, i))))
            }
            return .blob(Data())
        default:
            if let c = sqlite3_column_text(stmt, i) { return .text(String(cString: c)) }
            return .text("")
        }
    }
}
```

- [ ] **Step 2: Write the factory**

Create `Sources/SimpletonSQL/SQLDriverFactory.swift`:
```swift
// Sources/SimpletonSQL/SQLDriverFactory.swift
import Foundation
import SimpletonCore

/// Builds the right `SQLDriver` for a `Connection`. Postgres/MySQL cases are added in later tasks.
public enum SQLDriverFactory {
    public static func make(_ connection: Connection, secret: ConnectionSecret?) throws -> SQLDriver {
        switch connection.kind {
        case .sqlite:
            return SQLiteDriver(path: connection.params["path"] ?? "")
        case .postgres, .mysql:
            throw SQLDriverError.unsupported("\(connection.kind.rawValue) driver not yet implemented")
        default:
            throw SQLDriverError.unsupported("\(connection.kind.rawValue) is not a SQL connection")
        }
    }
}
```

- [ ] **Step 3: Add real SQLite checks (no server needed)**

Append to `runSQLDriverChecks` in `Tests/CoreChecks/SQLDriverChecks.swift` (add `import SimpletonCore` at top):
```swift
    func tempDBPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("corechecks-sql-\(UUID().uuidString).sqlite").path
    }

    await t.suite("SQLiteDriver end-to-end") {
        let path = tempDBPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let driver = SQLiteDriver(path: path)
        do {
            try await driver.connect()
            _ = try await driver.run(
                "CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT NOT NULL, score REAL, note TEXT)")
            if case .status(let n, _) = try await driver.run(
                "INSERT INTO t (name, score, note) VALUES ('a', 1.5, NULL)") {
                t.expectEqual(n, 1, "insert affected 1")
            } else {
                t.expect(false, "insert should return .status")
            }
            if case .rows(let cols, let rows) = try await driver.run("SELECT id, name, score, note FROM t") {
                t.expectEqual(cols.map(\.name), ["id", "name", "score", "note"], "column names")
                t.expectEqual(rows.count, 1, "one row")
                t.expectEqual(rows[0][0], SQLValue.integer(1), "id integer")
                t.expectEqual(rows[0][1], SQLValue.text("a"), "name text")
                t.expectEqual(rows[0][2], SQLValue.double(1.5), "score double")
                t.expectEqual(rows[0][3], SQLValue.null, "note null")
            } else {
                t.expect(false, "select should return .rows")
            }
            let tables = try await driver.tables(in: nil)
            t.expect(tables.contains(TableInfo(name: "t", kind: .table)), "table t listed")
            let columns = try await driver.columns(of: "t", in: nil)
            t.expectEqual(columns.first?.name, "id", "first column id")
            t.expect(columns.first?.isPrimaryKey == true, "id is primary key")
            t.expect(columns.contains { $0.name == "name" && !$0.nullable }, "name is NOT NULL")
            await driver.close()
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    t.suite("SQLDriverFactory mapping") {
        do {
            let sqlite = try SQLDriverFactory.make(Connection(name: "s", kind: .sqlite, params: ["path": "/tmp/x.sqlite"]), secret: nil)
            t.expect(sqlite is SQLiteDriver, "sqlite → SQLiteDriver")
        } catch {
            t.expect(false, "sqlite factory should not throw: \(error)")
        }
        do {
            _ = try SQLDriverFactory.make(Connection(name: "s3", kind: .s3), secret: nil)
            t.expect(false, "s3 should throw unsupported")
        } catch let e as SQLDriverError {
            if case .unsupported = e { t.expect(true, "s3 → unsupported") } else { t.expect(false, "wrong error \(e)") }
        } catch {
            t.expect(false, "wrong error type: \(error)")
        }
    }
```

- [ ] **Step 4: Build + checks**

Run: `swift build 2>&1 | tail -3` → `Build complete!`
Run: `swift run CoreChecks 2>&1 | tail -1` → all pass (SQLite suite runs for real).

- [ ] **Step 5: Lint + commit**

```bash
swift format lint --recursive --parallel --strict Sources Tests || swift format --in-place --recursive Sources Tests
git add Sources/SimpletonSQL/SQLiteDriver.swift Sources/SimpletonSQL/SQLDriverFactory.swift Tests/CoreChecks/SQLDriverChecks.swift
git commit -m "feat(sql): add SQLite driver and driver factory"
```

---

## Task 3: SQL panel shell (connect + editor + results grid, SQLite end-to-end)

**Files:**
- Create: `Sources/Simpleton/Panels/SQL/SQLPanelModel.swift`, `SQLPanelView.swift`, `SQLResultsGrid.swift`, `SQLConnectionEditor.swift`
- Modify: `Sources/Simpleton/Panels/BuiltInPanels.swift`, `Sources/Simpleton/Panels/PanelProfile.swift`, `Sources/Simpleton/AppDelegate.swift`

**Interfaces:**
- Consumes: `SQLDriver`/`SQLDriverFactory`/`QueryResult`/`SQLValue`/`Column` (`SimpletonSQL`); `Connection`/`ConnectionKind`/`ConnectionStore`/`CredentialStore`/`ConnectionSecret` (`SimpletonCore`); `ClientPanelScaffold`/`ClientAvailability` (app); `PanelContext.appSupportDir`.
- Produces: `SQLPanelView(appSupportDir: URL)`; `PanelDefinition.sql`; `PanelProfile.PanelID.sql = "sql"`.

- [ ] **Step 1: Write the panel model**

Create `Sources/Simpleton/Panels/SQL/SQLPanelModel.swift`:
```swift
// Sources/Simpleton/Panels/SQL/SQLPanelModel.swift
import Foundation
import SimpletonCore
import SimpletonSQL

@MainActor
final class SQLPanelModel: ObservableObject {
    @Published var connections: [Connection] = []
    @Published var selectedID: UUID?
    @Published var queryText: String = ""
    @Published var result: QueryResult?
    @Published var errorMessage: String?
    @Published var isConnecting = false
    @Published var isConnected = false
    @Published var showingEditor = false

    private let store: ConnectionStore
    private var driver: SQLDriver?

    /// The SQL kinds this panel manages.
    static let sqlKinds: Set<ConnectionKind> = [.sqlite, .postgres, .mysql]

    init(appSupportDir: URL) {
        self.store = ConnectionStore(directory: appSupportDir)
    }

    var selectedConnection: Connection? {
        guard let selectedID else { return nil }
        return connections.first { $0.id == selectedID }
    }

    var availability: ClientAvailability {
        if isConnecting { return .loading }
        if isConnected { return .ready }
        if let errorMessage {
            return .unavailable(
                icon: "cylinder.split.1x2", title: "Not connected", message: errorMessage,
                actionLabel: "Connections", action: { [weak self] in self?.showingEditor = true })
        }
        return .unavailable(
            icon: "cylinder.split.1x2", title: "No connection",
            message: "Pick a SQL connection or add one.", actionLabel: "New connection",
            action: { [weak self] in self?.showingEditor = true })
    }

    func reload() async {
        let all = await store.all()
        connections = all.filter { Self.sqlKinds.contains($0.kind) }
        if selectedID == nil { selectedID = connections.first?.id }
    }

    func connect() async {
        guard let connection = selectedConnection else { return }
        await disconnect()
        isConnecting = true
        errorMessage = nil
        let secret = CredentialStore.secret(for: connection.id)
        do {
            let d = try SQLDriverFactory.make(connection, secret: secret)
            try await d.connect()
            driver = d
            isConnected = true
        } catch {
            errorMessage = Self.describe(error)
        }
        isConnecting = false
    }

    func disconnect() async {
        if let driver { await driver.close() }
        driver = nil
        isConnected = false
        result = nil
    }

    func runQuery() async {
        guard let driver else { return }
        let sql = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sql.isEmpty else { return }
        errorMessage = nil
        do {
            result = try await driver.run(sql)
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// Heuristic: a non-SELECT/EXPLAIN/PRAGMA/WITH statement modifies data.
    var queryModifiesData: Bool {
        let head = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().prefix(while: { !$0.isWhitespace })
        return !["select", "explain", "pragma", "with", "show", "describe", "desc"].contains(String(head))
    }

    func saveConnection(_ connection: Connection, secret: ConnectionSecret?) async {
        try? await store.add(connection)
        if let secret { CredentialStore.store(secret, for: connection.id) }
        await reload()
        selectedID = connection.id
    }

    private static func describe(_ error: Error) -> String {
        if let e = error as? SQLDriverError {
            switch e {
            case .connectionFailed(let m): return m
            case .queryFailed(let m): return m
            case .notConnected: return "Not connected."
            case .unsupported(let m): return m
            }
        }
        return "\(error)"
    }
}
```

- [ ] **Step 2: Write the results grid**

Create `Sources/Simpleton/Panels/SQL/SQLResultsGrid.swift`:
```swift
// Sources/Simpleton/Panels/SQL/SQLResultsGrid.swift
import SimpletonSQL
import SwiftUI

/// A generic (unknown-columns) results grid for a `QueryResult`.
struct SQLResultsGrid: View {
    let result: QueryResult?

    var body: some View {
        switch result {
        case .none:
            emptyHint("Run a query to see results.")
        case .status(let affected, let message):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle").foregroundColor(DT.accentGreen)
                Text("\(affected) row\(affected == 1 ? "" : "s") affected — \(message)")
                    .font(DT.monoFont(size: 11)).foregroundColor(DT.textSecondary)
                Spacer()
            }
            .padding(8)
        case .rows(let columns, let rows):
            if rows.isEmpty {
                emptyHint("No rows.")
            } else {
                grid(columns: columns, rows: rows)
            }
        }
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundColor(DT.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func grid(columns: [Column], rows: [[SQLValue]]) -> some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(columns.indices, id: \.self) { i in
                        cell(columns[i].name, header: true)
                    }
                }
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(rows[r].indices, id: \.self) { c in
                            cell(rows[r][c].displayString, header: false, isNull: rows[r][c] == .null)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func cell(_ text: String, header: Bool, isNull: Bool = false) -> some View {
        Text(text)
            .font(DT.monoFont(size: 11))
            .fontWeight(header ? .semibold : .regular)
            .foregroundColor(header ? DT.textPrimary : (isNull ? DT.textFaint : DT.textSecondary))
            .lineLimit(1)
            .frame(width: 160, alignment: .leading)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .overlay(Rectangle().fill(.black.opacity(0.08)).frame(height: 1), alignment: .bottom)
    }
}
```

- [ ] **Step 3: Write the connection editor**

Create `Sources/Simpleton/Panels/SQL/SQLConnectionEditor.swift`:
```swift
// Sources/Simpleton/Panels/SQL/SQLConnectionEditor.swift
import SimpletonCore
import SwiftUI

/// A sheet to add a SQL connection (SQLite path, or server host/port/user/password/database).
struct SQLConnectionEditor: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (Connection, ConnectionSecret?) -> Void

    @State private var kind: ConnectionKind = .postgres
    @State private var name = ""
    @State private var host = "localhost"
    @State private var port = ""
    @State private var username = ""
    @State private var password = ""
    @State private var database = ""
    @State private var sqlitePath = ""
    @State private var useTLS = false

    private let kinds: [ConnectionKind] = [.postgres, .mysql, .sqlite]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New SQL Connection").font(.headline).foregroundColor(DT.textPrimary)
            Picker("Type", selection: $kind) {
                ForEach(kinds, id: \.self) { Text($0.displayName).tag($0) }
            }
            .onChange(of: kind) { if port.isEmpty, let p = kind.defaultPort { port = String(p) } }
            TextField("Name", text: $name).textFieldStyle(.roundedBorder)

            if kind == .sqlite {
                HStack {
                    TextField("Database file path", text: $sqlitePath).textFieldStyle(.roundedBorder)
                    Button("Choose…") { chooseFile() }
                }
            } else {
                HStack {
                    TextField("Host", text: $host).textFieldStyle(.roundedBorder)
                    TextField("Port", text: $port).textFieldStyle(.roundedBorder).frame(width: 80)
                }
                TextField("Database", text: $database).textFieldStyle(.roundedBorder)
                TextField("User", text: $username).textFieldStyle(.roundedBorder)
                SecureField("Password", text: $password).textFieldStyle(.roundedBorder)
                Toggle("Use TLS", isOn: $useTLS)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(name.isEmpty)
            }
        }
        .padding(16).frame(width: 380)
    }

    private func chooseFile() {
        let p = NSOpenPanel()
        p.canChooseFiles = true; p.canChooseDirectories = false; p.allowsMultipleSelection = false
        if p.runModal() == .OK, let url = p.url { sqlitePath = url.path }
    }

    private func save() {
        var params: [String: String] = [:]
        if kind == .sqlite {
            params["path"] = sqlitePath
        } else {
            params["database"] = database
            params["useTLS"] = useTLS ? "true" : "false"
        }
        let connection = Connection(
            name: name, kind: kind,
            host: kind == .sqlite ? nil : host,
            port: kind == .sqlite ? nil : Int(port),
            username: kind == .sqlite ? nil : username,
            params: params)
        let secret = (kind == .sqlite || password.isEmpty) ? nil : ConnectionSecret(password: password)
        onSave(connection, secret)
        dismiss()
    }
}
```

- [ ] **Step 4: Write the panel view**

Create `Sources/Simpleton/Panels/SQL/SQLPanelView.swift`:
```swift
// Sources/Simpleton/Panels/SQL/SQLPanelView.swift
import SimpletonCore
import SwiftUI

/// The SQL client panel: connection picker + query editor + results grid, hosted in the shared
/// client-panel chrome. Schema browser + history are layered on in a later task.
struct SQLPanelView: View {
    @StateObject private var model: SQLPanelModel

    init(appSupportDir: URL) {
        _model = StateObject(wrappedValue: SQLPanelModel(appSupportDir: appSupportDir))
    }

    var body: some View {
        ClientPanelScaffold(
            title: "SQL",
            availability: model.availability,
            autoRefresh: nil,
            onRefresh: { await model.reload() }
        ) {
            content
        }
        .sheet(isPresented: $model.showingEditor) {
            SQLConnectionEditor { connection, secret in
                Task { await model.saveConnection(connection, secret: secret) }
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            connectionBar
            ThemedDivider()
            editor
            ThemedDivider()
            SQLResultsGrid(result: model.result)
        }
    }

    private var connectionBar: some View {
        HStack(spacing: 6) {
            Picker("", selection: $model.selectedID) {
                Text("Select…").tag(UUID?.none)
                ForEach(model.connections, id: \.id) { c in
                    Text("\(c.name) (\(c.kind.displayName))").tag(UUID?.some(c.id))
                }
            }
            .labelsHidden()
            Button(model.isConnected ? "Disconnect" : "Connect") {
                Task { model.isConnected ? await model.disconnect() : await model.connect() }
            }
            .disabled(model.selectedID == nil)
            Button { model.showingEditor = true } label: { Image(systemName: "plus") }
                .buttonStyle(.plain).help("New connection")
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }

    private var editor: some View {
        VStack(spacing: 4) {
            TextEditor(text: $model.queryText)
                .font(DT.monoFont(size: 12))
                .frame(height: 90)
                .scrollContentBackground(.hidden)
            HStack {
                if model.queryModifiesData && !model.queryText.isEmpty {
                    Label("modifies data", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 10)).foregroundColor(DT.accentRed)
                }
                Spacer()
                Button("Run  ⌘↵") { Task { await model.runQuery() } }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.isConnected)
            }
            if let err = model.errorMessage, model.isConnected {
                Text(err).font(DT.monoFont(size: 10)).foregroundColor(DT.accentRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }
}
```

- [ ] **Step 5: Register the panel**

In `Sources/Simpleton/Panels/PanelProfile.swift`, add to the `PanelID` enum:
```swift
        static let sql = "sql"
```
In `Sources/Simpleton/Panels/BuiltInPanels.swift`, add a definition (alongside the others):
```swift
    static let sql = PanelDefinition(
        id: PanelProfile.PanelID.sql,
        name: "SQL",
        icon: "cylinder.split.1x2",
        description: "Query databases (SQLite, Postgres, MySQL)",
        defaultSide: .right,
        isBuiltIn: true
    ) { context in
        NSHostingController(rootView: SQLPanelView(appSupportDir: context.appSupportDir))
    }
```
In `Sources/Simpleton/AppDelegate.swift`, after `panelRegistry.register(.docker)`:
```swift
        panelRegistry.register(.sql)
```
In `Sources/Simpleton/Panels/PanelProfile.swift` `defaultProfiles`, add `"sql"` to the **Developer** profile's `rightPanelIDs` (making the right rail show it):
```swift
            rightPanelIDs: ["sql"],
```

- [ ] **Step 6: Build + checks + manual runtime**

Run: `swift build 2>&1 | tail -3` → `Build complete!`
Run: `swift run CoreChecks 2>&1 | tail -1` → all pass (no regression).
Manual: launch the app, switch to the Developer profile, open the SQL panel from the right rail; add a SQLite connection to a temp `.db`; Connect; run `CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT); INSERT INTO t(name) VALUES('x');` then `SELECT * FROM t` — grid shows the row; a non-SELECT shows the "N rows affected" banner; a bad query shows the inline error.

- [ ] **Step 7: Lint + commit**

```bash
swift format lint --recursive --parallel --strict Sources Tests || swift format --in-place --recursive Sources Tests
git add Sources/Simpleton/Panels/SQL Sources/Simpleton/Panels/BuiltInPanels.swift Sources/Simpleton/Panels/PanelProfile.swift Sources/Simpleton/AppDelegate.swift
git commit -m "feat(sql): add SQL panel shell with connection editor and results grid"
```

---

## Task 4: Schema browser + query history

**Files:**
- Create: `Sources/SimpletonSQL/SQLQueryHistoryStore.swift`, `Sources/Simpleton/Panels/SQL/SQLSchemaBrowser.swift`
- Modify: `Sources/Simpleton/Panels/SQL/SQLPanelModel.swift`, `SQLPanelView.swift`; `Tests/CoreChecks/SQLDriverChecks.swift`

**Interfaces:**
- Consumes: `SQLDriver.databases()/tables(in:)/columns(of:in:)`; `TableInfo`/`ColumnInfo`.
- Produces: `SQLQueryHistoryStore(directory:)` with `record(_:for:) / history(for:)`; `SQLSchemaBrowser`.

- [ ] **Step 1: Write the history store**

Create `Sources/SimpletonSQL/SQLQueryHistoryStore.swift`:
```swift
// Sources/SimpletonSQL/SQLQueryHistoryStore.swift
import Foundation

/// Per-connection query history, persisted to `sql-history.json` in the support dir (last 50 per
/// connection id). Tolerant Codable so schema growth never drops existing history.
public actor SQLQueryHistoryStore {
    private let fileURL: URL
    private var byConnection: [String: [String]] = [:]
    private var loaded = false
    private let maxPerConnection = 50

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("sql-history.json")
    }

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode(HistoryFile.self, from: data)
        else { return }
        byConnection = decoded.byConnection
    }

    public func history(for connectionID: UUID) -> [String] {
        ensureLoaded()
        return byConnection[connectionID.uuidString] ?? []
    }

    public func record(_ query: String, for connectionID: UUID) {
        ensureLoaded()
        let key = connectionID.uuidString
        var list = byConnection[key] ?? []
        list.removeAll { $0 == query }
        list.insert(query, at: 0)
        if list.count > maxPerConnection { list = Array(list.prefix(maxPerConnection)) }
        byConnection[key] = list
        try? save()
    }

    private func save() throws {
        let data = try JSONEncoder().encode(HistoryFile(byConnection: byConnection))
        try data.write(to: fileURL, options: .atomic)
    }

    private struct HistoryFile: Codable {
        var version: Int = 1
        var byConnection: [String: [String]] = [:]
        init(byConnection: [String: [String]]) { self.byConnection = byConnection }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
            byConnection = try c.decodeIfPresent([String: [String]].self, forKey: .byConnection) ?? [:]
        }
    }
}
```

- [ ] **Step 2: History-store checks**

Append to `runSQLDriverChecks`:
```swift
    await t.suite("SQLQueryHistoryStore record/dedup/cap/persist") {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("corechecks-sqlhist-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        let store = SQLQueryHistoryStore(directory: dir)
        await store.record("SELECT 1", for: id)
        await store.record("SELECT 2", for: id)
        await store.record("SELECT 1", for: id)  // dedup → moves to front
        let h = await store.history(for: id)
        t.expectEqual(h.first, "SELECT 1", "most recent first after dedup")
        t.expectEqual(h.count, 2, "deduped to two entries")
        let reloaded = SQLQueryHistoryStore(directory: dir)
        t.expectEqual(await reloaded.history(for: id).count, 2, "persisted across instances")
    }
```

- [ ] **Step 3: Wire history into the model**

In `SQLPanelModel`, add `private let history: SQLQueryHistoryStore` (init from `appSupportDir`), a `@Published var historyItems: [String] = []`, load it in `connect()` (`historyItems = await history.history(for: connection.id)`), and in `runQuery()` on success record + refresh:
```swift
        do {
            result = try await driver.run(sql)
            if let id = selectedConnection?.id {
                await history.record(sql, for: id)
                historyItems = await history.history(for: id)
            }
        } catch { errorMessage = Self.describe(error) }
```
Add a `loadSchema()` that fills `@Published var schema: [SchemaNode]` (see Step 4) after connect.

- [ ] **Step 4: Write the schema browser**

Create `Sources/Simpleton/Panels/SQL/SQLSchemaBrowser.swift`:
```swift
// Sources/Simpleton/Panels/SQL/SQLSchemaBrowser.swift
import SimpletonSQL
import SwiftUI

/// A lazy schema tree: tables/views → columns. Clicking a table inserts a starter SELECT.
struct SQLSchemaBrowser: View {
    let tables: [TableInfo]
    let columnsByTable: [String: [ColumnInfo]]
    let onExpand: (String) -> Void
    let onPickTable: (String) -> Void

    @State private var expanded: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(tables, id: \.name) { table in
                    Button {
                        toggle(table.name)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: expanded.contains(table.name) ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8)).foregroundColor(DT.textTertiary)
                            Image(systemName: table.kind == .view ? "eye" : "tablecells")
                                .font(.system(size: 10)).foregroundColor(DT.textTertiary)
                            Text(table.name).font(DT.monoFont(size: 11)).foregroundColor(DT.textSecondary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture(count: 2).onEnded { onPickTable(table.name) })
                    if expanded.contains(table.name) {
                        ForEach(columnsByTable[table.name] ?? [], id: \.name) { col in
                            HStack(spacing: 4) {
                                Text(col.name).font(DT.monoFont(size: 10)).foregroundColor(DT.textTertiary)
                                Text(col.type).font(DT.monoFont(size: 9)).foregroundColor(DT.textFaint)
                                Spacer()
                            }
                            .padding(.leading, 22)
                        }
                    }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
        }
        .scrollContentBackground(.hidden)
    }

    private func toggle(_ table: String) {
        if expanded.contains(table) { expanded.remove(table) } else { expanded.insert(table); onExpand(table) }
    }
}
```
In the model add `@Published var tables: [TableInfo] = []` and `@Published var columnsByTable: [String: [ColumnInfo]] = [:]`; `loadSchema()` sets `tables = try await driver.tables(in: nil)`; an `expand(table:)` fills `columnsByTable[table] = try await driver.columns(of: table, in: nil)`; a `pickTable(_:)` sets `queryText = "SELECT * FROM \(table) LIMIT 100"`.

- [ ] **Step 5: Show the browser + history in the view**

In `SQLPanelView.content`, place `SQLSchemaBrowser` above the editor (bounded height, e.g. `.frame(maxHeight: 160)`), wired to `model.tables` / `model.columnsByTable` / `model.expand` / `model.pickTable`; add a small history menu/list from `model.historyItems` that sets `model.queryText`. Call `await model.loadSchema()` at the end of `connect()`.

- [ ] **Step 6: Build + checks + manual**

Run: `swift build 2>&1 | tail -3` → `Build complete!`; `swift run CoreChecks 2>&1 | tail -1` → all pass (history suite runs).
Manual: connect to the SQLite DB from Task 3; the schema tree lists `t`; expanding shows columns; double-clicking inserts `SELECT * FROM t LIMIT 100`; after running, the query appears in history and re-selecting it refills the editor.

- [ ] **Step 7: Lint + commit**

```bash
swift format lint --recursive --parallel --strict Sources Tests || swift format --in-place --recursive Sources Tests
git add Sources/SimpletonSQL/SQLQueryHistoryStore.swift Sources/Simpleton/Panels/SQL Tests/CoreChecks/SQLDriverChecks.swift
git commit -m "feat(sql): add schema browser and per-connection query history"
```

---

## Task 5: `PostgresDriver` (PostgresNIO) + integration-gated checks + wire into UI

**Files:**
- Create: `Sources/SimpletonSQL/SQLEventLoop.swift`, `Sources/SimpletonSQL/PostgresDriver.swift`
- Modify: `Sources/SimpletonSQL/SQLDriverFactory.swift`; `Tests/CoreChecks/SQLDriverChecks.swift`

**Interfaces:**
- Consumes: `SQLDriver` + models; `Connection`/`ConnectionSecret`. Verified PostgresNIO 1.33.1 API: `PostgresConnection.connect(on:configuration:id:logger:) async throws`; `PostgresConnection.Configuration(host:port:username:password:database:tls:)` with `tls: .disable | .require(NIOSSLContext)`; `conn.query(PostgresQuery(unsafeSQL:), logger:) async throws -> PostgresRowSequence` (`.collect() -> [PostgresRow]`); `PostgresRow` is a `Sequence` of `PostgresCell` (`.columnName`, `.bytes`, `.dataType`, `.decode(_:)`); `conn.close() async throws`.
- Produces: `SQLEventLoop.shared`; `PostgresDriver(connection:secret:)`.

- [ ] **Step 1: Shared event loop group**

Create `Sources/SimpletonSQL/SQLEventLoop.swift`:
```swift
// Sources/SimpletonSQL/SQLEventLoop.swift
import NIOPosix

/// Process-wide event loop group shared by the NIO-based SQL drivers (Postgres/MySQL). Created
/// lazily; lives for the process lifetime (no explicit shutdown — the app owns it until exit).
public enum SQLEventLoop {
    public static let shared = MultiThreadedEventLoopGroup(numberOfThreads: 1)
}
```

- [ ] **Step 2: Write the Postgres driver**

Create `Sources/SimpletonSQL/PostgresDriver.swift`:
```swift
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
        guard case .rows(_, let rows) = try await run(
            "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname")
        else { return [] }
        return rows.compactMap { $0.first?.displayString }
    }

    public func tables(in database: String?) async throws -> [TableInfo] {
        guard case .rows(_, let rows) = try await run(
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
        let escaped = table.replacingOccurrences(of: "'", with: "''")
        guard case .rows(_, let rows) = try await run(
            "SELECT column_name, data_type, is_nullable FROM information_schema.columns "
                + "WHERE table_name = '\(escaped)' ORDER BY ordinal_position")
        else { return [] }
        return rows.compactMap { row in
            guard row.count >= 3 else { return nil }
            return ColumnInfo(
                name: row[0].displayString, type: row[1].displayString,
                nullable: row[2].displayString.uppercased() == "YES", isPrimaryKey: false)
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
```

- [ ] **Step 3: Add the `.postgres` factory case**

In `SQLDriverFactory.swift`, split the combined case:
```swift
        case .postgres:
            return try PostgresDriver(connection: connection, secret: secret)
        case .mysql:
            throw SQLDriverError.unsupported("mysql driver not yet implemented")
```

- [ ] **Step 4: Integration-gated Postgres check**

Append to `runSQLDriverChecks` (add a URL→Connection helper once, reused by Task 6):
```swift
    func parseSQLURL(_ raw: String, kind: ConnectionKind) -> (Connection, ConnectionSecret?)? {
        guard let c = URLComponents(string: raw), let host = c.host else { return nil }
        let db = c.path.hasPrefix("/") ? String(c.path.dropFirst()) : c.path
        let conn = Connection(
            name: "test", kind: kind, host: host, port: c.port,
            username: c.user, params: ["database": db, "useTLS": "false"])
        let secret = c.password.map { ConnectionSecret(password: $0) }
        return (conn, secret)
    }

    if let url = ProcessInfo.processInfo.environment["SIMPLETON_PG_TEST_URL"],
        let (conn, secret) = parseSQLURL(url, kind: .postgres) {
        await t.suite("PostgresDriver SELECT 1 (integration)") {
            do {
                let driver = try SQLDriverFactory.make(conn, secret: secret)
                try await driver.connect()
                if case .rows(let cols, let rows) = try await driver.run("SELECT 1 AS n") {
                    t.expectEqual(cols.first?.name, "n", "column name n")
                    t.expectEqual(rows.first?.first, SQLValue.integer(1), "value 1")
                } else {
                    t.expect(false, "SELECT should return rows")
                }
                _ = try await driver.tables(in: nil)  // smoke: schema query runs
                await driver.close()
            } catch {
                t.expect(false, "unexpected error: \(error)")
            }
        }
    } else {
        print("  … PostgresDriver checks skipped (set SIMPLETON_PG_TEST_URL to run)")
    }
```

- [ ] **Step 5: Build + checks + manual**

Run: `swift build 2>&1 | tail -3` → `Build complete!`
Run: `swift run CoreChecks 2>&1 | tail -3` → all pass; without the env var it prints the Postgres skip line.
Optional integration: `SIMPLETON_PG_TEST_URL="postgres://user:pass@localhost:5432/db" swift run CoreChecks` → the Postgres suite runs green against a real server.
Manual: in the app, add a Postgres connection in the editor, Connect, browse schema, run `SELECT * FROM <table> LIMIT 100`.

- [ ] **Step 6: Lint + commit**

```bash
swift format lint --recursive --parallel --strict Sources Tests || swift format --in-place --recursive Sources Tests
git add Sources/SimpletonSQL/SQLEventLoop.swift Sources/SimpletonSQL/PostgresDriver.swift Sources/SimpletonSQL/SQLDriverFactory.swift Tests/CoreChecks/SQLDriverChecks.swift
git commit -m "feat(sql): add PostgreSQL driver via PostgresNIO"
```

---

## Task 6: `MySQLDriver` (MySQLNIO) + integration-gated checks + wire into UI

**Files:**
- Create: `Sources/SimpletonSQL/MySQLDriver.swift`
- Modify: `Sources/SimpletonSQL/SQLDriverFactory.swift`; `Tests/CoreChecks/SQLDriverChecks.swift`

**Interfaces:**
- Consumes: `SQLDriver` + models; `Connection`/`ConnectionSecret`; `SQLEventLoop.shared` (Task 5). Verified MySQLNIO 1.9.1 API (**no native async — bridge every future with `.get()`**): `MySQLConnection.connect(to: SocketAddress, username:, database:, password:, tlsConfiguration:, serverHostname:, logger:, on:) -> EventLoopFuture<MySQLConnection>`; `SocketAddress.makeAddressResolvingHost(_:port:)`; `conn.query(_ sql:_ binds:onMetadata:) -> EventLoopFuture<[MySQLRow]>` with `MySQLQueryMetadata.affectedRows: UInt64`; `MySQLRow.columnDefinitions[i].name`, `row.column(_ name:) -> MySQLData?` (`.string`, `.description`); `conn.close() -> EventLoopFuture<Void>`.
- Produces: `MySQLDriver(connection:secret:)`.

- [ ] **Step 1: Write the MySQL driver**

Create `Sources/SimpletonSQL/MySQLDriver.swift`:
```swift
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

    public func run(_ sql: String) async throws -> QueryResult {
        guard let connection else { throw SQLDriverError.notConnected }
        do {
            var affected: UInt64 = 0
            let rows = try await connection.query(sql, [], onMetadata: { affected = $0.affectedRows }).get()
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

    public func databases() async throws -> [String] {
        guard case .rows(_, let rows) = try await run("SHOW DATABASES") else { return [] }
        return rows.compactMap { $0.first?.displayString }
    }

    public func tables(in database: String?) async throws -> [TableInfo] {
        guard case .rows(_, let rows) = try await run("SHOW FULL TABLES") else { return [] }
        return rows.compactMap { row in
            guard let name = row.first?.displayString else { return nil }
            let kind: TableKind = row.count > 1 && row[1].displayString.uppercased().contains("VIEW") ? .view : .table
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
```

- [ ] **Step 2: Add the `.mysql` factory case**

In `SQLDriverFactory.swift`, replace the `.mysql` throw with:
```swift
        case .mysql:
            return try MySQLDriver(connection: connection, secret: secret)
```

- [ ] **Step 3: Integration-gated MySQL check**

Append to `runSQLDriverChecks` (reuses `parseSQLURL` from Task 5):
```swift
    if let url = ProcessInfo.processInfo.environment["SIMPLETON_MYSQL_TEST_URL"],
        let (conn, secret) = parseSQLURL(url, kind: .mysql) {
        await t.suite("MySQLDriver SELECT 1 (integration)") {
            do {
                let driver = try SQLDriverFactory.make(conn, secret: secret)
                try await driver.connect()
                if case .rows(let cols, let rows) = try await driver.run("SELECT 1 AS n") {
                    t.expectEqual(cols.first?.name, "n", "column name n")
                    t.expectEqual(rows.first?.first?.displayString, "1", "value 1")
                } else {
                    t.expect(false, "SELECT should return rows")
                }
                _ = try await driver.tables(in: nil)
                await driver.close()
            } catch {
                t.expect(false, "unexpected error: \(error)")
            }
        }
    } else {
        print("  … MySQLDriver checks skipped (set SIMPLETON_MYSQL_TEST_URL to run)")
    }
```

- [ ] **Step 4: Build + checks + manual**

Run: `swift build 2>&1 | tail -3` → `Build complete!`
Run: `swift run CoreChecks 2>&1 | tail -3` → all pass; prints the MySQL skip line without the env var.
Optional integration: `SIMPLETON_MYSQL_TEST_URL="mysql://user:pass@127.0.0.1:3306/db" swift run CoreChecks`.
Manual: add a MySQL connection, Connect, browse schema, run a SELECT and an INSERT (banner shows the affected-row count from `onMetadata`).

- [ ] **Step 5: Lint + commit**

```bash
swift format lint --recursive --parallel --strict Sources Tests || swift format --in-place --recursive Sources Tests
git add Sources/SimpletonSQL/MySQLDriver.swift Sources/SimpletonSQL/SQLDriverFactory.swift Tests/CoreChecks/SQLDriverChecks.swift
git commit -m "feat(sql): add MySQL driver via MySQLNIO"
```

---

## Task 7: Final verification

**Files:** none (verification only).

- [ ] **Step 1: Full build** — `swift build 2>&1 | tail -3` → `Build complete!`
- [ ] **Step 2: Full checks** — `swift run CoreChecks 2>&1 | tail -3` → all pass; the SQLite/history suites run for real; Postgres/MySQL print skip lines (or run green with the env vars set).
- [ ] **Step 3: Lint gate** — `swift format lint --recursive --parallel --strict Sources Tests` → exit 0.
- [ ] **Step 4: Headless e2e smoke** — `bash scripts/e2e/workspace-e2e.sh` → `SIMP-WSE2E RESULT PASS` (app still launches/drives a workspace after adding the SQL panel + SimpletonSQL target).

---

## Self-Review

**Spec coverage**
- §2 scope (connect/disconnect, browse, run SQL incl. writes, results grid, affected-row feedback, history, connection editor) → Tasks 3 (shell + writes + affected-row banner + editor), 4 (browse + history), 5–6 (engines). Non-goals excluded.
- §4 module structure (`SimpletonSQL` lib + app UI, NIO out of `SimpletonCore`) → Task 1.
- §5 drivers (SQLite/Postgres/MySQL) → Tasks 2, 5, 6; NIO lifecycle (shared ELG) → Task 5; factory → Task 2 (extended in 5/6).
- §4 `SQLDriver` seam + models → Task 1.
- §6 panel UI (scaffold, picker, editor, results, writes indicator, history) → Tasks 3–4.
- §8 history store → Task 4.
- §9 error handling (map to `SQLDriverError`, inline/unavailable surfacing) → drivers (2/5/6) + model (3).
- §10 testing (SQLite real; Postgres/MySQL integration-gated skip-clean) → Tasks 1–6; final gate → Task 7.
- §3 deps exact-pinned + `Package.resolved` → Task 1.

**Placeholder scan:** no TBD/TODO; every code step carries full source; verification steps are concrete commands with expected output. The two "MVP note" comments (Postgres PK/exotic-type text fallback; MySQL text-typed cells) are explicit, intentional scope limits, not deferred work.

**Type consistency:** `SQLDriver` method names (`connect/databases/tables(in:)/columns(of:in:)/run/close`) identical across protocol (T1) and all three drivers (T2/5/6). `QueryResult`/`SQLValue`/`Column`/`TableInfo`/`ColumnInfo`/`SQLDriverError` used identically everywhere. `SQLDriverFactory.make(_:secret:)` signature stable across T2→T5→T6 (cases filled in progressively; no rename). `ClientPanelScaffold(title:availability:autoRefresh:onRefresh:content:)` + `ClientAvailability.unavailable(icon:title:message:actionLabel:action:)` match the shipped Phase 0 API. `Connection(name:kind:host:port:username:params:)`, `ConnectionStore.all()`, `CredentialStore.secret(for:)/store(_:for:)`, `ConnectionSecret(password:)` match Phase 0. `runSQLDriverChecks` is async and registered once (T1); `parseSQLURL` defined in T5, reused in T6.
