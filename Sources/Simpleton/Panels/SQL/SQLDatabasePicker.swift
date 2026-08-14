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
