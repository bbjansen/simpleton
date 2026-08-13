// Sources/Simpleton/Panels/Connections/DataConnectionsHostController.swift
import AppKit
import SimpletonCore
import SwiftUI

/// Hosts the SwiftUI DataConnectionsPanel for embedding in the AppKit panel split.
final class DataConnectionsHostController: NSViewController {
    private let appSupportDir: URL
    private let bookmarkStore: BookmarkStore?
    private let onLaunch: (Connection, ConnectionLaunch) -> Void

    init(
        appSupportDir: URL, bookmarkStore: BookmarkStore?,
        onLaunch: @escaping (Connection, ConnectionLaunch) -> Void
    ) {
        self.appSupportDir = appSupportDir
        self.bookmarkStore = bookmarkStore
        self.onLaunch = onLaunch
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let panel = DataConnectionsPanel(
            appSupportDir: appSupportDir, bookmarkStore: bookmarkStore, onLaunch: onLaunch)
        self.view = NSHostingView(rootView: panel)
        self.view.frame = NSRect(x: 0, y: 0, width: 240, height: 600)
    }
}
