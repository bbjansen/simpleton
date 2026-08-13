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
            if let db = self.db {
                sqlite3_close(db)
                self.db = nil
            }
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
            return ColumnInfo(
                name: row[1].displayString, type: row[2].displayString, nullable: !notnull, isPrimaryKey: pk)
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
