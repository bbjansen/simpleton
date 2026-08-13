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
    @Published var historyItems: [String] = []
    @Published var tables: [TableInfo] = []
    @Published var columnsByTable: [String: [ColumnInfo]] = [:]

    private let store: ConnectionStore
    private let history: SQLQueryHistoryStore
    private var driver: SQLDriver?

    /// The SQL kinds this panel manages.
    static let sqlKinds: Set<ConnectionKind> = [.sqlite, .postgres, .mysql]

    init(appSupportDir: URL) {
        self.store = ConnectionStore(directory: appSupportDir)
        self.history = SQLQueryHistoryStore(directory: appSupportDir)
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

    /// Open a specific connection by id (from the Data Connections manager): select it and connect.
    func openConnection(id: UUID) async {
        await reload()
        if connections.contains(where: { $0.id == id }) {
            selectedID = id
            await connect()
        }
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
            historyItems = await history.history(for: connection.id)
            await loadSchema()
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
        tables = []
        columnsByTable = [:]
    }

    func runQuery() async {
        guard let driver else { return }
        let sql = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sql.isEmpty else { return }
        errorMessage = nil
        do {
            result = try await driver.run(sql)
            if let id = selectedConnection?.id {
                await history.record(sql, for: id)
                historyItems = await history.history(for: id)
            }
        } catch {
            errorMessage = Self.describe(error)
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
