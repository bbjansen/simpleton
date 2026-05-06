// Sources/Simpleton/Views/QuickConnectPanel.swift
import AppKit
import SwiftUI
import SimpletonCore

/// Floating panel for Cmd+K quick connect — fuzzy search bookmarks with frecency ranking.
final class QuickConnectPanel {

    private var panel: NSPanel?
    private var bookmarkStore: BookmarkStore
    private var config: AppConfig
    private var onSelect: ((Bookmark) -> Void)?

    init(bookmarkStore: BookmarkStore, config: AppConfig) {
        self.bookmarkStore = bookmarkStore
        self.config = config
    }

    func show(relativeTo window: NSWindow?, onSelect: @escaping (Bookmark) -> Void) {
        self.onSelect = onSelect
        dismiss()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = NSColor(white: 0.12, alpha: 0.98)
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = false

        let contentView = QuickConnectContentView(
            bookmarkStore: bookmarkStore,
            onSelect: { [weak self] bookmark in
                self?.dismiss()
                self?.onSelect?(bookmark)
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )
        panel.contentView = NSHostingView(rootView: contentView)

        // Position centered on the parent window
        if let window = window {
            let windowFrame = window.frame
            let x = windowFrame.midX - 250
            let y = windowFrame.midY + 50
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.center()
        }

        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func dismiss() {
        panel?.close()
        panel = nil
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }
}

// MARK: - SwiftUI Content

struct QuickConnectContentView: View {
    let bookmarkStore: BookmarkStore
    let onSelect: (Bookmark) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var results: [Bookmark] = []
    @State private var selectedIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Quick connect...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .onSubmit { selectCurrent() }
                    .onChange(of: query) { _ in search() }

                Text("⌘K")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(4)
            }
            .padding(14)
            .background(Color.white.opacity(0.05))

            Divider().background(Color.white.opacity(0.1))

            // Results
            if results.isEmpty && !query.isEmpty {
                VStack {
                    Spacer()
                    Text("No connections found")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(Array(results.enumerated()), id: \.element.id) { index, bookmark in
                        QuickConnectRow(bookmark: bookmark, isSelected: index == selectedIndex)
                            .id(bookmark.id)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(bookmark) }
                    }
                    .listStyle(.plain)
                    .onChange(of: selectedIndex) { newIndex in
                        if newIndex < results.count {
                            proxy.scrollTo(results[newIndex].id, anchor: .center)
                        }
                    }
                }
            }

            // Footer
            Divider().background(Color.white.opacity(0.1))
            HStack(spacing: 16) {
                Text("↑↓ navigate")
                Text("↵ connect")
                Text("esc close")
            }
            .font(.system(size: 10))
            .foregroundColor(Color.white.opacity(0.3))
            .padding(8)
        }
        .frame(width: 500, height: 400)
        .background(Color(nsColor: NSColor(white: 0.12, alpha: 1)))
        .onAppear { search() }
        .onExitCommand { onDismiss() }
        .background(KeyEventHandler(
            onUpArrow: { moveSelection(-1) },
            onDownArrow: { moveSelection(1) }
        ))
    }

    private func search() {
        Task {
            if query.isEmpty {
                // Show recent + pinned when no query
                let pinned = await bookmarkStore.pinnedBookmarks()
                let all = await bookmarkStore.allBookmarks()
                results = pinned + all.filter { !$0.pinned }
            } else {
                results = await bookmarkStore.search(query: query)
            }
            selectedIndex = 0
        }
    }

    private func selectCurrent() {
        guard selectedIndex < results.count else { return }
        onSelect(results[selectedIndex])
    }

    private func moveSelection(_ delta: Int) {
        let newIndex = selectedIndex + delta
        if newIndex >= 0 && newIndex < results.count {
            selectedIndex = newIndex
        }
    }
}

struct QuickConnectRow: View {
    let bookmark: Bookmark
    let isSelected: Bool

    var body: some View {
        HStack {
            Circle()
                .fill(bookmark.pinned ? Color.green : Color.gray)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(bookmark.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : .primary)

                Text(SSHManager.connectionTitle(for: bookmark))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !bookmark.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(bookmark.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 9))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(8)
                    }
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(6)
    }
}

/// Captures arrow key events in SwiftUI for list navigation.
struct KeyEventHandler: NSViewRepresentable {
    let onUpArrow: () -> Void
    let onDownArrow: () -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onUpArrow = onUpArrow
        view.onDownArrow = onDownArrow
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.onUpArrow = onUpArrow
        nsView.onDownArrow = onDownArrow
    }

    class KeyCaptureView: NSView {
        var onUpArrow: (() -> Void)?
        var onDownArrow: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 126: onUpArrow?() // up arrow
            case 125: onDownArrow?() // down arrow
            default: super.keyDown(with: event)
            }
        }
    }
}
