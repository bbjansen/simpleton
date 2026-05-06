// Sources/Simpleton/Views/SidebarHostController.swift
import AppKit
import SwiftUI
import SimpletonCore

/// NSViewController that hosts the SwiftUI SidebarView for embedding in AppKit NSSplitView.
final class SidebarHostController: NSViewController {

    private let bookmarkStore: BookmarkStore
    private let sshConfigWatcher: SSHConfigWatcher?
    private let config: AppConfig
    var onConnect: ((Bookmark) -> Void)?
    var onNewConnection: (() -> Void)?

    init(bookmarkStore: BookmarkStore, sshConfigWatcher: SSHConfigWatcher?, config: AppConfig) {
        self.bookmarkStore = bookmarkStore
        self.sshConfigWatcher = sshConfigWatcher
        self.config = config
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let sidebar = SidebarView(
            bookmarkStore: bookmarkStore,
            sshConfigWatcher: sshConfigWatcher,
            onConnect: { [weak self] bookmark in
                self?.onConnect?(bookmark)
            },
            onNewConnection: { [weak self] in
                self?.onNewConnection?()
            }
        )
        self.view = NSHostingView(rootView: sidebar)
        self.view.frame = NSRect(x: 0, y: 0, width: 240, height: 600)
    }
}
