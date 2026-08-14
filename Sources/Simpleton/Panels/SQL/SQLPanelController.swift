// Sources/Simpleton/Panels/SQL/SQLPanelController.swift
import AppKit
import SwiftUI

/// NSViewController that owns one `SQLPanelModel` and hosts the drawer `SQLPanelView(model:)`.
///
/// The model used to be a `@StateObject` inside `SQLPanelView`, so the live driver / connection /
/// schema / result were private to that view and couldn't be shared. Lifting the model here — owned
/// by the container's cached controller — lets the standalone `SQLWorkspaceView` bind to the SAME
/// instance (via `model`), so the drawer and the workspace are two views of one live session.
/// Mirrors `AIChatPanelController`: the container's `sqlPanelController` accessor reaches this to
/// hand the model to the Expand → workspace window.
final class SQLPanelController: NSViewController {

    /// The one model this panel owns. `SQLWorkspaceView(model:)` binds to the same instance.
    let model: SQLPanelModel

    init(appSupportDir: URL) {
        self.model = SQLPanelModel(appSupportDir: appSupportDir)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let host = NSHostingView(rootView: SQLPanelView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 600)
        self.view = host
    }
}
