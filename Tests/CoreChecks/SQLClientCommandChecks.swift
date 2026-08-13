// Tests/CoreChecks/SQLClientCommandChecks.swift
import Foundation
import SimpletonCore
import SimpletonSQL

func runSQLClientCommandChecks(_ t: TestRunner) {
    t.suite("SQLClientCommand.candidates") {
        t.expectEqual(SQLClientCommand.candidates(for: .postgres), ["pgcli", "psql"], "postgres TUI→std")
        t.expectEqual(SQLClientCommand.candidates(for: .mysql), ["mycli", "mysql"], "mysql TUI→std")
        t.expectEqual(SQLClientCommand.candidates(for: .sqlite), ["litecli", "sqlite3"], "sqlite TUI→std")
        t.expect(SQLClientCommand.candidates(for: .s3).isEmpty, "s3 has no CLI client")
    }

    t.suite("SQLClientCommand.build — password goes to env, never args") {
        let pg = Connection(
            name: "p", kind: .postgres, host: "db", port: 5432, username: "app",
            params: ["database": "appdb"])
        let built = SQLClientCommand.build(for: pg, password: "s3cret")
        t.expect(built != nil, "postgres builds")
        t.expectEqual(built?.args, ["-h", "db", "-p", "5432", "-U", "app", "-d", "appdb"], "pg args")
        t.expectEqual(built?.environment, ["PGPASSWORD=s3cret"], "pg password in env")
        t.expect(!(built?.args.contains("s3cret") ?? true), "password NOT in args")

        let my = Connection(
            name: "m", kind: .mysql, host: "h", port: 3306, username: "u", params: ["database": "d"])
        let mb = SQLClientCommand.build(for: my, password: "pw")
        t.expectEqual(mb?.environment, ["MYSQL_PWD=pw"], "mysql password in env")
        t.expect(!(mb?.args.contains("pw") ?? true), "mysql password NOT in args")

        let lite = Connection(name: "l", kind: .sqlite, params: ["path": "/tmp/x.db"])
        let lb = SQLClientCommand.build(for: lite, password: nil)
        t.expectEqual(lb?.args, ["/tmp/x.db"], "sqlite args = path")
        t.expect(lb?.environment.isEmpty ?? false, "sqlite no env")

        t.expect(
            SQLClientCommand.build(for: Connection(name: "s", kind: .s3), password: nil) == nil,
            "s3 → nil")
    }

    t.suite("SQLClientCommand.build — conninfo-looking database is dropped, not passed to psql") {
        let evil = Connection(
            name: "e", kind: .postgres, host: "db", port: 5432, username: "u",
            params: ["database": "host=evil.example.com dbname=y"])
        let built = SQLClientCommand.build(for: evil, password: "pw")
        t.expect(!(built?.args.contains("-d") ?? true), "conninfo-looking db is not passed as -d")
        t.expect(
            !(built?.args.contains(where: { $0.contains("evil") }) ?? true),
            "attacker host never reaches argv")
        // A plain name still passes.
        let ok = Connection(
            name: "o", kind: .postgres, host: "db", username: "u", params: ["database": "appdb"])
        t.expect(SQLClientCommand.build(for: ok, password: nil)?.args.contains("appdb") ?? false, "plain db passes")
    }
}
