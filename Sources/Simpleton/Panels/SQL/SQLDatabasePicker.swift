// Sources/Simpleton/Panels/SQL/SQLDatabasePicker.swift
import SimpletonSQL
import SwiftUI

/// The active-database switcher, shared by the drawer panel and the workspace toolbars. Shown only
/// when connected to an engine that exposes more than one database (so SQLite's single "main" hides
/// it). Selecting a database calls `model.selectDatabase`, which switches in place (MySQL `USE`) or
/// reconnects (Postgres) and reloads the schema.
struct SQLDatabasePicker: View {
    @ObservedObject var model: SQLPanelModel

    var body: some View {
        if model.isConnected && model.databases.count > 1 {
            Picker("", selection: selection) {
                ForEach(model.databases, id: \.self) { db in Text(db).tag(db) }
            }
            .labelsHidden().fixedSize().help("Active database")
            .disabled(model.isConnecting)
        }
    }

    /// A binding that reads the active database (falling back to the first known one so the menu never
    /// shows blank) and routes a change through the model's switch/reconnect path.
    private var selection: Binding<String> {
        Binding(
            get: {
                let current = model.selectedDatabase ?? ""
                return model.databases.contains(current) ? current : (model.databases.first ?? "")
            },
            set: { newValue in Task { await model.selectDatabase(newValue) } }
        )
    }
}

/// The active-schema switcher (Postgres `search_path`), shown only for engines that expose a schema
/// layer distinct from the database — MySQL/SQLite report no schemas, so it stays hidden. Selecting a
/// schema calls `model.selectSchema`, which switches live and reloads the schema tree.
struct SQLSchemaPicker: View {
    @ObservedObject var model: SQLPanelModel

    var body: some View {
        if model.isConnected && model.schemas.count > 1 {
            Picker("", selection: selection) {
                ForEach(model.schemas, id: \.self) { s in Text(s).tag(s) }
            }
            .labelsHidden().fixedSize().help("Active schema")
            .disabled(model.isConnecting)
        }
    }

    private var selection: Binding<String> {
        Binding(
            get: {
                let current = model.selectedSchema ?? ""
                return model.schemas.contains(current) ? current : (model.schemas.first ?? "")
            },
            set: { newValue in Task { await model.selectSchema(newValue) } }
        )
    }
}
