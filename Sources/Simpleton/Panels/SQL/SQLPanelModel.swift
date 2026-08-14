// Sources/Simpleton/Panels/SQL/SQLPanelModel.swift
import Foundation
import SimpletonCore
import SimpletonSQL

/// A results grid we've proven safe to edit: one real table, a known primary key, and result
/// columns that all map to real table columns. Produced only by `SQLPanelModel.detectEditable` and
/// only when every guard passes — its mere existence is the edit affordance for the UI.
struct EditableTarget: Equatable {
    /// The (unquoted) table name UPDATEs target.
    let table: String
    /// The primary-key column names (in table order); every one is present in `resultColumns`.
    let primaryKey: [String]
    /// The result-grid column names, in grid order. Each maps 1:1 to a real table column.
    let resultColumns: [String]
    /// The engine dialect, so the UPDATE builder emits the right placeholders + quoting.
    let dialect: SQLDialect
}

/// A single row's staged edit, resolved to concrete values: the primary-key values that identify the
/// row and the column/value pairs to write. Passed to `commitEdits`, which turns each into one
/// parameterized UPDATE.
struct RowEdit {
    let key: [(column: String, value: SQLValue)]
    let changes: [(column: String, value: SQLValue)]
}

/// The outcome of a commit: how many rows were written, or an error message that stopped it.
struct CommitOutcome: Equatable {
    let updatedRows: Int
    let errorMessage: String?
}

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
    @Published var historyItems: [String] = []
    @Published var tables: [TableInfo] = []
    @Published var columnsByTable: [String: [ColumnInfo]] = [:]
    /// Named, reusable queries the user saved for the connected database (see `SQLSavedQueryStore`).
    /// Loaded on connect, cleared on disconnect; the editor's bookmark menu applies/manages them.
    @Published var savedQueries: [SavedQuery] = []
    /// Non-nil exactly when the current result is a single-table SELECT with a primary key we can
    /// UPDATE by. The grid shows the edit affordance only while this is set. Recomputed on every
    /// `runQuery`; cleared on disconnect or any non-editable result.
    @Published var editable: EditableTarget?
    /// The navigable foreign-key cells for the current result, keyed by result-column index. Non-empty
    /// only when the result maps to a known source table (via editable detection) that declares
    /// single-column foreign keys whose columns are visible in the grid. Drives the grid's right-click
    /// "Go to <referencedTable>" action; recomputed on every query, cleared with the result.
    @Published var foreignKeyMatches: [Int: SQLForeignKeyMatcher.Match] = [:]
    /// Result of the most recent commit, surfaced to the UI (success count or an error to display).
    @Published var lastCommit: CommitOutcome?
    /// Monotonic wall-clock duration of the most recent successful query. nil before any run and after
    /// a failed run (the error is the signal then). Drives the editor's "N rows · X ms" readout.
    @Published var lastQueryDuration: TimeInterval?

    private let store: ConnectionStore
    private let history: SQLQueryHistoryStore
    private let savedStore: SQLSavedQueryStore
    private var driver: SQLDriver?

    /// The SQL kinds this panel manages.
    static let sqlKinds: Set<ConnectionKind> = [.sqlite, .postgres, .mysql]

    init(appSupportDir: URL) {
        self.store = ConnectionStore(directory: appSupportDir)
        self.history = SQLQueryHistoryStore(directory: appSupportDir)
        self.savedStore = SQLSavedQueryStore(directory: appSupportDir)
    }

    var selectedConnection: Connection? {
        guard let selectedID else { return nil }
        return connections.first { $0.id == selectedID }
    }

    /// A compact "N rows · 12 ms" (or "N affected · …") readout for the most recent successful run,
    /// or nil when there hasn't been one. Pairs `lastQueryDuration` with the current result shape.
    var lastRunSummary: String? {
        guard let seconds = lastQueryDuration else { return nil }
        switch result {
        case .rows(_, let rows):
            return SQLRunStats.summary(count: rows.count, noun: .rows, seconds: seconds)
        case .status(let affected, _):
            return SQLRunStats.summary(count: affected, noun: .affected, seconds: seconds)
        case .none:
            return SQLRunStats.timeText(seconds)
        }
    }

    /// Monotonic elapsed seconds since `start` (immune to wall-clock adjustments, unlike `Date()`).
    private static func elapsed(since start: DispatchTime) -> TimeInterval {
        Double(DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds) / 1_000_000_000
    }

    var availability: ClientAvailability {
        if isConnecting { return .loading }
        if isConnected { return .ready }
        // Only show the add-a-connection empty state when there are genuinely no saved SQL
        // connections. When connections exist but we are not connected, fall through to `.ready` so the
        // connection bar (picker + Connect) stays visible — otherwise a saved connection is
        // unreachable from the UI.
        if connections.isEmpty {
            return .unavailable(
                icon: "cylinder.split.1x2", title: "No connections",
                message: errorMessage ?? "Add a SQL connection to get started.",
                actionLabel: "New connection",
                action: { [weak self] in self?.showingEditor = true })
        }
        return .ready
    }

    func reload() async {
        let all = await store.all()
        connections = all.filter { Self.sqlKinds.contains($0.kind) }
        if selectedID == nil { selectedID = connections.first?.id }
    }

    /// Consume a pending "open this connection" request from the Data Connections manager (set in
    /// `PendingClientOpen` before the reveal notification). Guarded by the holder so it fires exactly
    /// once whether triggered by a cold mount (`.task`) or a warm notification (`.onReceive`), and
    /// only when the pending open targets the SQL panel.
    func consumePendingOpen() async {
        guard let pending = PendingClientOpen.shared.take(for: PanelProfile.PanelID.sql) else { return }
        await reload()
        if connections.contains(where: { $0.id == pending }) {
            selectedID = pending
            await connect()
        }
    }

    func connect() async {
        // Reentrancy guard: `isConnecting` is set synchronously (before any await) so a second
        // concurrent connect() — a double-click, or a reveal-remount re-firing .task — returns here
        // instead of racing and orphaning the first driver without closing it.
        guard !isConnecting, let connection = selectedConnection else { return }
        isConnecting = true
        defer { isConnecting = false }
        await disconnect()
        errorMessage = nil
        let secret = CredentialStore.secret(for: connection.id)
        do {
            let d = try SQLDriverFactory.make(connection, secret: secret)
            try await d.connect()
            driver = d
            isConnected = true
            historyItems = await history.history(for: connection.id)
            savedQueries = await savedStore.saved(for: connection.id)
            await loadSchema()
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    func disconnect() async {
        if let driver { await driver.close() }
        driver = nil
        isConnected = false
        result = nil
        editable = nil
        foreignKeyMatches = [:]
        lastCommit = nil
        lastQueryDuration = nil
        savedQueries = []
        tables = []
        columnsByTable = [:]
    }

    func runQuery() async {
        // A user-initiated run clears any prior commit banner; the refresh after a commit does not
        // (it goes through `refreshCurrentQuery`, which preserves `lastCommit`).
        lastCommit = nil
        await performQuery()
    }

    /// Run just the selected text / current statement (⌘⇧↵) without changing the editor content.
    func runSelection(_ sql: String) async {
        lastCommit = nil
        await performQuery(sql: sql)
    }

    /// Execute `sql` (defaulting to `queryText`), publish the result, and recompute editability.
    /// Shared by the user's Run action, Run-selection, and the post-commit refresh; the caller owns
    /// `lastCommit`.
    private func performQuery(sql overrideSQL: String? = nil) async {
        guard let driver else { return }
        let sql = (overrideSQL ?? queryText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sql.isEmpty else { return }
        errorMessage = nil
        let start = DispatchTime.now()
        do {
            let queryResult = try await driver.run(sql)
            lastQueryDuration = Self.elapsed(since: start)
            result = queryResult
            editable = await detectEditable(sql: sql, result: queryResult, driver: driver)
            foreignKeyMatches = await detectForeignKeys(result: queryResult, editable: editable, driver: driver)
            if let id = selectedConnection?.id {
                await history.record(sql, for: id)
                historyItems = await history.history(for: id)
            }
        } catch {
            lastQueryDuration = nil
            editable = nil
            foreignKeyMatches = [:]
            errorMessage = Self.describe(error)
        }
    }

    /// Compute the navigable FK cells for `result`. The source table is known only when editable
    /// detection resolved one (the same conservative single-table parse), so FKs are offered exactly
    /// then. Reads the table's declared foreign keys from the driver and matches them, by name, to the
    /// result columns via the pure `SQLForeignKeyMatcher`. Returns a column-index → match map for the
    /// grid; empty when there is no source table or no matching single-column FK.
    private func detectForeignKeys(
        result: QueryResult, editable: EditableTarget?, driver: SQLDriver
    ) async -> [Int: SQLForeignKeyMatcher.Match] {
        guard case .rows(let columns, _) = result, let editable else { return [:] }
        let fks = (try? await driver.foreignKeys(of: editable.table, in: nil)) ?? []
        guard !fks.isEmpty else { return [:] }
        let matches = SQLForeignKeyMatcher.matches(resultColumns: columns.map(\.name), foreignKeys: fks)
        return Dictionary(uniqueKeysWithValues: matches.map { ($0.columnIndex, $0) })
    }

    /// Navigate a foreign-key cell: set the query to `SELECT * FROM <refTable> WHERE <refCol> = ?` and
    /// run it with `value` BOUND as a parameter (never interpolated), then publish the referenced row.
    /// Identifiers are quoted per dialect; only the value crosses as a bind. NULL cells are skipped by
    /// the caller (there's nothing to match), so `value` here is always a concrete key. Records the
    /// generated SQL in the editor + history so the jump is transparent and reusable.
    func navigateForeignKey(referencedTable: String, referencedColumn: String, value: SQLValue) async {
        guard let driver else { return }
        if case .null = value { return }
        lastCommit = nil
        errorMessage = nil
        let dialect = driver.dialect
        let sql =
            "SELECT * FROM \(dialect.quoteIdentifier(referencedTable)) "
            + "WHERE \(dialect.quoteIdentifier(referencedColumn)) = \(dialect.placeholder(1))"
        queryText = sql
        let start = DispatchTime.now()
        do {
            let queryResult = try await driver.execute(sql, [value])
            lastQueryDuration = Self.elapsed(since: start)
            result = queryResult
            editable = await detectEditable(sql: sql, result: queryResult, driver: driver)
            foreignKeyMatches = await detectForeignKeys(result: queryResult, editable: editable, driver: driver)
            if let id = selectedConnection?.id {
                await history.record(sql, for: id)
                historyItems = await history.history(for: id)
            }
        } catch {
            lastQueryDuration = nil
            editable = nil
            foreignKeyMatches = [:]
            errorMessage = Self.describe(error)
        }
    }

    /// Decide whether `result` can be edited in place. Conservative on purpose: it returns non-nil
    /// ONLY when the query is a single-table SELECT (per `SQLEditableParser`), the table has a
    /// primary key, every result column maps to a real table column, and every PK column is present
    /// in the result (so each row can be UPDATE-d by its key). Any doubt → nil (read-only).
    private func detectEditable(sql: String, result: QueryResult, driver: SQLDriver) async -> EditableTarget? {
        guard case .rows(let columns, _) = result else { return nil }
        guard let parsed = SQLEditableParser.parse(sql) else { return nil }
        let tableColumns = (try? await driver.columns(of: parsed.table, in: nil)) ?? []
        // The reconciliation (real columns present, PK visible, no duplicates, projection matches) is
        // a pure function in SimpletonSQL, unit-tested headlessly; here we only supply live schema.
        guard
            let resolved = SQLEditableResolver.resolve(
                parsed: parsed, tableColumns: tableColumns, resultColumns: columns.map(\.name))
        else { return nil }
        return EditableTarget(
            table: resolved.table, primaryKey: resolved.primaryKey, resultColumns: resolved.resultColumns,
            dialect: driver.dialect)
    }

    /// Write staged edits as parameterized UPDATEs, then re-run the current query to refresh the grid.
    /// Each `RowEdit` becomes one `UPDATE … SET … WHERE <pk> = ?` via the driver's native bind path —
    /// values are bound, never interpolated. Stops at the first error and surfaces it; on full
    /// success, re-queries so the grid shows committed state. Publishes the outcome via `lastCommit`.
    func commitEdits(_ edits: [RowEdit]) async {
        guard let driver, let target = editable, !edits.isEmpty else { return }
        var written = 0
        do {
            for edit in edits {
                guard !edit.changes.isEmpty, !edit.key.isEmpty else { continue }
                let stmt = try SQLUpdateBuilder.build(
                    table: target.table, changes: edit.changes, keys: edit.key, dialect: target.dialect)
                _ = try await driver.execute(stmt.sql, stmt.params)
                written += 1
            }
            // Refresh via `performQuery` (not `runQuery`) so it doesn't clear the outcome we set next.
            await performQuery()
            lastCommit = CommitOutcome(updatedRows: written, errorMessage: nil)
        } catch {
            let message = Self.describe(error)
            errorMessage = message
            lastCommit = CommitOutcome(updatedRows: written, errorMessage: message)
        }
    }

    func loadSchema() async {
        guard let driver else { return }
        tables = (try? await driver.tables(in: nil)) ?? []
        columnsByTable = [:]
    }

    func expand(table: String) async {
        guard let driver, columnsByTable[table] == nil else { return }
        columnsByTable[table] = (try? await driver.columns(of: table, in: nil)) ?? []
    }

    func pickTable(_ table: String) {
        queryText = "SELECT * FROM \(table) LIMIT 100"
    }

    /// Save the current editor text as a named favorite for the connected database, then refresh the
    /// published list. No-ops when there's no selected connection, or the name/SQL is blank.
    func saveCurrentQuery(name: String) async {
        guard let id = selectedConnection?.id else { return }
        await savedStore.save(name: name, sql: queryText, for: id)
        savedQueries = await savedStore.saved(for: id)
    }

    /// Delete a saved favorite by name for the connected database, then refresh the published list.
    func removeSavedQuery(name: String) async {
        guard let id = selectedConnection?.id else { return }
        await savedStore.remove(name: name, for: id)
        savedQueries = await savedStore.saved(for: id)
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
        await connect()  // a freshly added connection connects + loads immediately
    }

    /// Connect to whatever is currently selected (or disconnect if the selection was cleared).
    /// Driven by the connection bar's selection change, so picking a database loads it immediately
    /// without a separate "Connect" click.
    func connectSelected() async {
        if selectedID == nil {
            await disconnect()
        } else {
            await connect()
        }
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
