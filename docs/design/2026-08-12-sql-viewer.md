# SQL Viewer — Design Spec

**Date:** 2026-08-12
**Status:** Approved
**Builds on:** Phase 0 client-viewer foundation (`Connection`/`ConnectionKind`/`ConnectionSecret`, `ConnectionStore`, `CredentialStore`, `ClientPanelScaffold`) — all shipped in v0.1.4.
**Decision context:** `docs/design/2026-08-12-plugin-architecture-research.md` (concluded: first-party native modules, not a third-party plugin runtime).

---

## 1. Goal & Scope

A native macOS **SQL client panel** — a **full query IDE** — for **SQLite, PostgreSQL, and MySQL**, built as the first first-party "viewer module". Connection picker, schema browser, query editor, results grid, writes, and per-connection history. Native Swift drivers (no external CLIs): SQLite via `libsqlite3`, Postgres via **PostgresNIO**, MySQL via **MySQLNIO**.

**In scope:** connect/disconnect; browse databases → tables/views → columns; run arbitrary SQL (SELECT and writes); paged results grid; affected-row feedback; per-connection query history; a connection editor to add/edit SQL connections (reusing Phase 0 storage).

**Non-goals (deliberately later or out):** the marketplace / licensing / payments layer (separate effort); autocomplete/IntelliSense; ER diagrams; query plan visualization; data export; multi-statement transaction management UI; SSH-tunneled DB connections (future — Phase 0 SSH bookmarks are separate).

## 2. Module Structure

Isolate the heavy DB dependencies and establish the per-viewer "module" pattern:

- **New SPM library target `SimpletonSQL`** — the pure **data layer** (no UI): the `SQLDriver` seam, the three drivers, the result/schema models, the driver factory, and the shared NIO `EventLoopGroup`. Depends on `SimpletonCore` + `PostgresNIO` + `MySQLNIO`. SQLite uses `import SQLite3` (system module on Apple platforms — no package).
- **SQL panel UI in the app** (`Sources/Simpleton/Panels/SQL/…`) — SwiftUI, reusing `ClientPanelScaffold` + `DT`, calling `SimpletonSQL`. Registered via `BuiltInPanels` + a `PanelProfile.PanelID.sql` constant, like every other panel.

This keeps SwiftNIO out of `SimpletonCore` and the core app modules, and means a future "downloadable first-party bundle" already has a clean seam.

## 3. Dependencies (exact-pinned per project standards)

`Package.swift`:
```swift
.package(url: "https://github.com/vapor/postgres-nio.git", exact: "1.33.1"),
.package(url: "https://github.com/vapor/mysql-nio.git", exact: "1.9.1"),
```
```swift
.target(
    name: "SimpletonSQL",
    dependencies: [
        "SimpletonCore",
        .product(name: "PostgresNIO", package: "postgres-nio"),
        .product(name: "MySQLNIO", package: "mysql-nio"),
    ]),
```
- The `Simpleton` executable target adds `"SimpletonSQL"` to its dependencies.
- The `CoreChecks` target adds `"SimpletonSQL"` to its dependencies (to test the driver layer).
- These introduce SwiftNIO transitively (the project resolves none today). Commit `Package.resolved`.

## 4. The `SQLDriver` seam + models (`SimpletonSQL`)

The internal, backend-agnostic interface the panel talks to (this is the `ClientProvider` idea, now an in-code abstraction, not a plugin boundary). All async; drivers run I/O off the main actor.

```swift
public protocol SQLDriver: AnyObject, Sendable {
    func connect() async throws
    func databases() async throws -> [String]                       // Postgres: DBs; MySQL: schemas; SQLite: attached ("main", …)
    func tables(in database: String?) async throws -> [TableInfo]
    func columns(of table: String, in database: String?) async throws -> [ColumnInfo]
    func run(_ sql: String) async throws -> QueryResult
    func close() async
}

public struct TableInfo: Sendable, Hashable { public let name: String; public let kind: TableKind }   // .table / .view
public struct ColumnInfo: Sendable, Hashable {
    public let name: String; public let type: String; public let nullable: Bool; public let isPrimaryKey: Bool
}

public enum SQLValue: Sendable, Hashable {
    case null, integer(Int64), double(Double), text(String), bool(Bool), blob(Data)
    public var displayString: String { /* null→"NULL", blob→"<N bytes>", etc. */ }
}
public struct Column: Sendable, Hashable { public let name: String; public let declaredType: String? }

public enum QueryResult: Sendable {
    case rows(columns: [Column], rows: [[SQLValue]])
    case status(affected: Int, message: String)          // non-SELECT: INSERT/UPDATE/DDL
}

public enum SQLDriverError: Error, Sendable {
    case connectionFailed(String), queryFailed(String), notConnected, unsupported(String)
}
```

Schema is **lazy** (`databases` → `tables(in:)` → `columns(of:in:)`) so the browser expands on demand rather than fetching everything up front.

## 5. Drivers

- **`SQLiteDriver`** — wraps the `libsqlite3` C API (`sqlite3_open_v2`, `sqlite3_prepare_v2`, `sqlite3_step`, column typing via `sqlite3_column_type`). Synchronous C calls are serialized on a dedicated `DispatchQueue` and exposed through the async protocol. `databases()` returns attached DBs (`PRAGMA database_list`); `tables(in:)` from `sqlite_master`; `columns(of:)` from `PRAGMA table_info`.
- **`PostgresDriver`** — PostgresNIO. Uses a single `PostgresConnection` on the shared `EventLoopGroup` (one connection per driver instance; not the pooled `PostgresClient`). `databases()` from `pg_database`; `tables(in:)`/`columns(of:)` from `information_schema`. Maps `PostgresRow` cells → `SQLValue`.
- **`MySQLDriver`** — MySQLNIO. `MySQLConnection.connect(...)` on the shared `EventLoopGroup`. `databases()` = `SHOW DATABASES`; tables/columns from `information_schema`. Maps `MySQLRow` → `SQLValue`.

**NIO lifecycle:** `SimpletonSQL` owns one process-wide `MultiThreadedEventLoopGroup` (`SQLEventLoop.shared`), created lazily and shut down on app termination. Connections are per-open-editor-session (one `SQLDriver` instance per active connection in the panel); `close()` releases it.

**Driver factory:**
```swift
public enum SQLDriverFactory {
    public static func make(_ connection: Connection, secret: ConnectionSecret?) throws -> SQLDriver
}
```
Builds params from the Phase-0 `Connection` (`host`/`port`/`username`/`params["database"]`, `params["useTLS"]`, SQLite `params["path"]`) + the `ConnectionSecret.password`. Throws `.unsupported` for non-SQL kinds.

## 6. Panel UI (Full IDE) — app target

Hosted in `ClientPanelScaffold` (title "SQL", `availability` = `.unavailable` when no connection is selected / connection failed, else `.ready`). Layout inside the content area:

- **Connection bar:** a picker over `ConnectionStore.byKind(.postgres/.mysql/.sqlite)` + Connect/Disconnect + a "＋ New connection" button opening the **connection editor**.
- **Schema browser** (leading, collapsible): lazy tree — databases → tables/views → columns — from the driver. Clicking a table can insert `SELECT * FROM <table> LIMIT 100` into the editor.
- **Query editor:** monospaced `TextEditor`, **⌘↵ runs** the current statement; a Run button. A subtle "modifies data" indicator when the statement isn't a `SELECT`/`WITH`/`EXPLAIN`/`PRAGMA` (heuristic) — the query still runs (it's an IDE).
- **Results:** for `.rows`, a virtualized grid (columns + rows, NULLs styled, blob as `<N bytes>`, horizontal scroll, first N rows with a "load more"/`LIMIT` note); for `.status`, an "N rows affected — <message>" banner; errors shown inline.
- **History** (per connection): recent queries, click to reload into the editor.

**Connection editor** (a sheet): kind picker (Postgres/MySQL/SQLite), then host/port/user/password/database (or a file picker for SQLite `path`). Saves the `Connection` via `ConnectionStore` and the password via `CredentialStore`. `ConnectionKind.defaultPort` prefills the port.

## 7. Data Flow

Panel selects a `Connection` → `SQLDriverFactory.make(connection, secret: CredentialStore.secret(for:))` → `driver.connect()` (async, off-main) → schema browser calls `databases()/tables/columns` lazily → editor `run(sql)` → `QueryResult` marshalled to the SwiftUI grid on the main actor. One driver instance per active connection; `close()` on disconnect / panel teardown.

## 8. Query History

`SQLQueryHistoryStore` (in `SimpletonSQL`) — persists the last 50 successful queries per `Connection.id` to `…/Simpleton/sql-history.json` (tolerant Codable, mirrors the store pattern). Read on connect, appended on successful `run`.

## 9. Error Handling

- **Connect failures** → `SQLDriverError.connectionFailed` → scaffold `.unavailable(reason:)` with the message; no crash.
- **Query failures** → `.queryFailed` → inline error banner under the editor; the panel stays usable.
- **Credentials missing** → prompt to open the connection editor.
- **NIO/driver exceptions** are caught at the driver boundary and mapped to `SQLDriverError`; never surfaced raw.

## 10. Testing

`SimpletonSQL` is added to the `CoreChecks` target. New `Tests/CoreChecks/SQLDriverChecks.swift`:
- **SQLite (fully real, no server):** create a temp `.sqlite` file, `connect`, `run` DDL + INSERT (`.status` affected count), `SELECT` (`.rows` with correct `SQLValue` typing incl. NULL/blob/int/text/double), `databases()/tables(in:)/columns(of:)` reflect the created schema. `SQLValue.displayString` cases.
- **`SQLDriverFactory`** maps each `ConnectionKind` to the right driver; throws `.unsupported` for `.s3`/`.ftp`/etc.
- **Postgres/MySQL:** integration-gated — probe a local server via env (`SIMPLETON_PG_TEST_URL` / `SIMPLETON_MYSQL_TEST_URL`); **skip cleanly with a printed note when absent** (same guard pattern as the `CredentialStore` Keychain checks), so CI never fails for lack of a DB.

UI (panel, editor, grid, schema tree, connection editor) is verified by `swift build` + manual runtime; no headless UI assertions.

## 11. File Structure

**Create**
- `Sources/SimpletonSQL/SQLDriver.swift` — protocol + models (`TableInfo`, `ColumnInfo`, `SQLValue`, `Column`, `QueryResult`, `SQLDriverError`).
- `Sources/SimpletonSQL/SQLEventLoop.swift` — shared `EventLoopGroup`.
- `Sources/SimpletonSQL/SQLiteDriver.swift`
- `Sources/SimpletonSQL/PostgresDriver.swift`
- `Sources/SimpletonSQL/MySQLDriver.swift`
- `Sources/SimpletonSQL/SQLDriverFactory.swift`
- `Sources/SimpletonSQL/SQLQueryHistoryStore.swift`
- `Sources/Simpleton/Panels/SQL/SQLPanelView.swift` — the IDE shell in `ClientPanelScaffold`
- `Sources/Simpleton/Panels/SQL/SQLSchemaBrowser.swift`
- `Sources/Simpleton/Panels/SQL/SQLResultsGrid.swift`
- `Sources/Simpleton/Panels/SQL/SQLConnectionEditor.swift`
- `Sources/Simpleton/Panels/SQL/SQLPanelModel.swift` — `@MainActor ObservableObject` orchestrating driver + state
- `Tests/CoreChecks/SQLDriverChecks.swift`

**Modify**
- `Package.swift` — add the two packages + `SimpletonSQL` target; add `SimpletonSQL` to `Simpleton` and `CoreChecks` deps.
- `Sources/Simpleton/Panels/BuiltInPanels.swift` — register the SQL panel definition.
- `Sources/Simpleton/Panels/PanelProfile.swift` — add `PanelID.sql`; optionally include in a default profile.
- `Tests/CoreChecks/main.swift` — register `runSQLDriverChecks`.

## 12. Build Order (for the plan)

1. **Deps + `SimpletonSQL` skeleton** — Package.swift wiring + `SQLDriver` protocol/models; build resolves NIO.
2. **`SQLiteDriver` + factory + CoreChecks** — fully testable, no server.
3. **Panel shell** — `ClientPanelScaffold` + connection picker + editor + results grid, SQLite end-to-end.
4. **Schema browser + query history.**
5. **`PostgresDriver`** (+ integration-gated checks) and wire into the UI.
6. **`MySQLDriver`** (+ integration-gated checks) and wire into the UI.

## 13. Resolved Decisions

- **First-party native module** (not a third-party plugin runtime) — per the research doc.
- **Native drivers:** SQLite `libsqlite3`; Postgres **PostgresNIO 1.33.1**; MySQL **MySQLNIO 1.9.1** (exact-pinned).
- **Scope:** full query IDE (browse + editor + results + **writes** + history), all three engines.
- **Module boundary:** `SimpletonSQL` library (data) + app-target UI, keeping NIO out of `SimpletonCore`.
- **Marketplace/licensing:** separate later effort; does not gate this work.
