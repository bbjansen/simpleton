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
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = NSColor(red: 0.051, green: 0.051, blue: 0.078, alpha: 0.98)
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = false

        // Strong shadow for Spotlight/Raycast feel
        if let shadow = NSShadow() as NSShadow? {
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
            shadow.shadowBlurRadius = 40
            shadow.shadowOffset = NSSize(width: 0, height: -10)
            panel.setValue(shadow, forKey: "shadow")
        }

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
            let x = windowFrame.midX - 260
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
    @State private var isAppeared = false

    var body: some View {
        VStack(spacing: 0) {
            // Search field — large, no border, just bottom divider
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(DT.textMuted)
                    .font(.system(size: 15, weight: .medium))
                AutoFocusTextField(text: $query, placeholder: "Quick connect...", onSubmit: selectCurrent)
                    .font(.system(size: 18))
                    .onChange(of: query) { search() }

                Text("\u{2318}K")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(DT.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(DT.elevated)
                    .cornerRadius(5)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            Rectangle()
                .fill(DT.border.opacity(0.5))
                .frame(height: 0.5)

            // Results
            if results.isEmpty && !query.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22))
                        .foregroundColor(DT.textFaint)
                    Text("No connections found")
                        .font(.system(size: 13))
                        .foregroundColor(DT.textMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, bookmark in
                                QuickConnectRow(bookmark: bookmark, isSelected: index == selectedIndex)
                                    .id(bookmark.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onSelect(bookmark) }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                    .onChange(of: selectedIndex) { _, newIndex in
                        if newIndex < results.count {
                            proxy.scrollTo(results[newIndex].id, anchor: .center)
                        }
                    }
                }
            }

            // Footer
            Rectangle()
                .fill(DT.border.opacity(0.5))
                .frame(height: 0.5)
            HStack(spacing: 20) {
                footerHint(keys: "\u{2191}\u{2193}", label: "navigate")
                footerHint(keys: "\u{21A9}", label: "connect")
                footerHint(keys: "esc", label: "close")
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
        }
        .frame(width: 520, height: 420)
        .background(DT.base)
        .clipShape(RoundedRectangle(cornerRadius: DT.radiusPanel))
        .overlay(
            RoundedRectangle(cornerRadius: DT.radiusPanel)
                .stroke(DT.panelBorder, lineWidth: 0.5)
        )
        .opacity(isAppeared ? 1 : 0)
        .scaleEffect(isAppeared ? 1 : 0.97)
        .onAppear {
            search()
            withAnimation(.easeOut(duration: 0.2)) {
                isAppeared = true
            }
        }
        .onExitCommand { onDismiss() }
        .background(KeyEventHandler(
            onUpArrow: { moveSelection(-1) },
            onDownArrow: { moveSelection(1) }
        ))
    }

    private func footerHint(keys: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(DT.textFaint)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(DT.elevated)
                .cornerRadius(3)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(DT.textFaint)
        }
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

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: bookmark.pinned ? "star.fill" : "network")
                .font(.system(size: 11))
                .foregroundColor(bookmark.pinned ? Color.yellow.opacity(0.8) : DT.textMuted)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(bookmark.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DT.textPrimary)

                Text(SSHManager.connectionTitle(for: bookmark))
                    .font(.system(size: 12))
                    .foregroundColor(DT.textTertiary)
            }

            Spacer()

            if !bookmark.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(bookmark.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 8, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundColor(DT.accentIndigo.opacity(0.9))
                            .background(DT.accentIndigo.opacity(0.15))
                            .cornerRadius(DT.radiusPill)
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: DT.radiusCard)
                .fill(isSelected ? DT.accentIndigo.opacity(0.12) : (isHovered ? DT.hover : Color.clear))
        )
        .onHover { hovering in
            withAnimation(DT.hoverAnimation) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Auto-focus TextField

struct AutoFocusTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 18, weight: .light)
        field.textColor = .white
        field.delegate = context.coordinator
        // Auto-focus after a brief delay to ensure the panel is key
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: AutoFocusTextField
        init(_ parent: AutoFocusTextField) { self.parent = parent }
        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                parent.text = field.stringValue
            }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
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
