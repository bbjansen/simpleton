// Sources/SimpletonSQL/SQLClientCommand.swift
import Foundation
import SimpletonCore

/// Pure builder for launching a terminal CLI client for a `Connection`. The password is placed in
/// the process ENVIRONMENT (PGPASSWORD/MYSQL_PWD), never on argv, so it can't leak via `ps` or shell
/// history. Executable *resolution* (which candidate is on disk) happens in the app; this is pure.
public enum SQLClientCommand {
    /// Preferred → fallback executables per kind (nicer TUI first, standard client second).
    public static func candidates(for kind: ConnectionKind) -> [String] {
        switch kind {
        case .postgres: return ["pgcli", "psql"]
        case .mysql: return ["mycli", "mysql"]
        case .sqlite: return ["litecli", "sqlite3"]
        default: return []
        }
    }

    /// Build (args, environment) for the resolved executable of `connection.kind`. The same args
    /// work for both the TUI and the standard client of each family. Returns nil for non-SQL kinds.
    public static func build(
        for connection: Connection, password: String?
    ) -> (
        args: [String], environment: [String]
    )? {
        switch connection.kind {
        case .postgres:
            var args = ["-h", connection.host ?? "localhost", "-p", String(connection.port ?? 5432)]
            if let u = connection.username { args += ["-U", u] }
            // Only pass a plain database name — never a libpq conninfo/URI string (which would let a
            // `host=…` in the field silently redirect the connection + leak PGPASSWORD elsewhere).
            if let db = connection.params["database"], isPlainDBName(db) { args += ["-d", db] }
            let env = password.map { ["PGPASSWORD=\($0)"] } ?? []
            return (args, env)
        case .mysql:
            var args = ["-h", connection.host ?? "127.0.0.1", "-P", String(connection.port ?? 3306)]
            if let u = connection.username { args += ["-u", u] }
            if let db = connection.params["database"], isPlainDBName(db) { args += [db] }
            let env = password.map { ["MYSQL_PWD=\($0)"] } ?? []
            return (args, env)
        case .sqlite:
            return ([connection.params["path"] ?? ""], [])
        default:
            return nil
        }
    }

    /// A safe, plain database name: non-empty, no leading `-` (would parse as an option), and no
    /// `=`/whitespace/`://` (which libpq would interpret as a full conninfo/URI string).
    private static func isPlainDBName(_ db: String) -> Bool {
        guard !db.isEmpty, !db.hasPrefix("-") else { return false }
        return !db.contains(where: { $0 == "=" || $0 == " " || $0 == "\t" }) && !db.contains("://")
    }
}
