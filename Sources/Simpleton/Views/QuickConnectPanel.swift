// Sources/Simpleton/Views/QuickConnectPanel.swift
import AppKit
import SimpletonCore
import SwiftUI

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

        // Create the panel once and reuse it
        if panel == nil {
            let newPanel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newPanel.isFloatingPanel = true
            newPanel.level = .floating
            newPanel.titleVisibility = .hidden
            newPanel.titlebarAppearsTransparent = true
            newPanel.isMovableByWindowBackground = false
            newPanel.backgroundColor = .clear
            newPanel.isOpaque = false
            newPanel.hasShadow = true
            newPanel.becomesKeyOnlyIfNeeded = false
            // NOTE: no `setValue(_, forKey: "shadow")` — NSWindow isn't KVC-compliant for "shadow",
            // so it raised NSUnknownKeyException (swallowed by AppKit's run loop) and silently
            // aborted the panel. Shadow is already enabled via `hasShadow = true`.

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
            newPanel.contentView = NSHostingView(rootView: contentView)
            self.panel = newPanel
            // Dismiss when the panel loses focus (user clicks away).
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: newPanel, queue: .main
            ) { [weak self] _ in
                self?.dismiss()
            }
        }

        guard let panel = panel else { return }

        // Position centered on the parent window
        if let window = window {
            let windowFrame = window.frame
            let x = windowFrame.midX - 260
            let y = windowFrame.midY + 50
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.center()
        }

        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        // Fade out, then orderOut (hides without deallocating). Guard on isVisible so the
        // resign-key observer can't re-enter.
        guard let panel = panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup(
            { ctx in
                ctx.duration = 0.15
                panel.animator().alphaValue = 0
            },
            completionHandler: { [weak panel] in
                panel?.orderOut(nil)
                panel?.alphaValue = 1
            })
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }
}

// MARK: - SwiftUI Content

struct QuickConnectContentView: View {
    @ObservedObject private var themeSettings = ThemeSettings.shared  // re-render on live theme change
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
                AutoFocusTextField(
                    text: $query, placeholder: "Quick connect...",
                    onSubmit: selectCurrent,
                    onMoveUp: { moveSelection(-1) },
                    onMoveDown: { moveSelection(1) },
                    onCancel: onDismiss
                )
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
        .frostedPanel(cornerRadius: DT.radiusPanel)
        .opacity(isAppeared ? 1 : 0)
        .scaleEffect(isAppeared ? 1 : 0.97)
        .onAppear {
            search()
            withAnimation(.easeOut(duration: 0.2)) {
                isAppeared = true
            }
        }
        .onExitCommand { onDismiss() }
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
    var onMoveUp: (() -> Void)? = nil
    var onMoveDown: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 18, weight: .light)
        field.textColor = .labelColor
        field.delegate = context.coordinator
        // Auto-focus after a brief delay to ensure the panel is key
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
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
        // The search field is first responder, so arrow / enter / escape arrive here as field-editor
        // commands. Route them to list-navigation callbacks — a sibling key view never sees them.
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.moveUp(_:)):
                if let up = parent.onMoveUp { up(); return true }
            case #selector(NSResponder.moveDown(_:)):
                if let down = parent.onMoveDown { down(); return true }
            case #selector(NSResponder.cancelOperation(_:)):
                if let cancel = parent.onCancel { cancel(); return true }
            default:
                break
            }
            return false
        }
    }
}
