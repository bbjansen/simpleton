// Sources/Simpleton/Views/CommandPalettePanel.swift
import AppKit
import SwiftUI
import SimpletonCore

struct PaletteAction: Identifiable {
    let id = UUID()
    let title: String
    let shortcut: String?
    let category: String
    let action: () -> Void
}

/// Floating panel for Cmd+Shift+P — fuzzy search all app actions.
final class CommandPalettePanel {

    private var panel: NSPanel?
    private var actions: [PaletteAction] = []

    func show(relativeTo window: NSWindow?, actions: [PaletteAction]) {
        self.actions = actions
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
        panel.backgroundColor = NSColor(white: 0.11, alpha: 0.98)
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = false

        let contentView = CommandPaletteContentView(
            actions: actions,
            onSelect: { [weak self] action in
                self?.dismiss()
                action.action()
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )
        panel.contentView = NSHostingView(rootView: contentView)

        if let window = window {
            let windowFrame = window.frame
            panel.setFrameOrigin(NSPoint(x: windowFrame.midX - 260, y: windowFrame.midY + 50))
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

struct CommandPaletteContentView: View {
    let actions: [PaletteAction]
    let onSelect: (PaletteAction) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var isAppeared = false

    private var filtered: [PaletteAction] {
        if query.isEmpty { return actions }
        let q = query.lowercased()
        return actions.filter {
            $0.title.lowercased().contains(q) || $0.category.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 10) {
                Image(systemName: "command")
                    .foregroundColor(Color.white.opacity(0.35))
                    .font(.system(size: 12, weight: .medium))
                AutoFocusTextField(text: $query, placeholder: "Type a command...", onSubmit: selectCurrent)
                    .font(.system(size: 16))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.04))

            Divider().background(Color.white.opacity(0.08))

            // Results
            ScrollViewReader { proxy in
                List(Array(filtered.enumerated()), id: \.element.id) { index, action in
                    CommandPaletteRow(action: action, isSelected: index == selectedIndex)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(action) }
                        .id(action.id)
                }
                .listStyle(.plain)
                .onChange(of: selectedIndex) { newIndex in
                    if newIndex < filtered.count {
                        proxy.scrollTo(filtered[newIndex].id, anchor: .center)
                    }
                }
            }

            // Footer
            Divider().background(Color.white.opacity(0.08))
            HStack(spacing: 20) {
                footerHint(keys: "\u{2191}\u{2193}", label: "navigate")
                footerHint(keys: "\u{21A9}", label: "select")
                footerHint(keys: "esc", label: "close")
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
        }
        .frame(width: 520, height: 420)
        .background(Color(nsColor: NSColor(white: 0.11, alpha: 1)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(isAppeared ? 1 : 0)
        .scaleEffect(isAppeared ? 1 : 0.97)
        .onAppear {
            withAnimation(.easeOut(duration: 0.2)) {
                isAppeared = true
            }
        }
        .onChange(of: query) { _ in selectedIndex = 0 }
        .onExitCommand { onDismiss() }
        .background(KeyEventHandler(
            onUpArrow: {
                if selectedIndex > 0 { selectedIndex -= 1 }
            },
            onDownArrow: {
                if selectedIndex < filtered.count - 1 { selectedIndex += 1 }
            }
        ))
    }

    private func footerHint(keys: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.3))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.white.opacity(0.06))
                .cornerRadius(3)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Color.white.opacity(0.25))
        }
    }

    private func selectCurrent() {
        let items = filtered
        guard selectedIndex < items.count else { return }
        onSelect(items[selectedIndex])
    }
}

// MARK: - Category badge colors

private func categoryColor(for category: String) -> Color {
    switch category.lowercased() {
    case "window": return .blue
    case "ssh": return .green
    case "view": return .purple
    case "edit": return .orange
    case "file": return .cyan
    case "help": return .yellow
    default: return .gray
    }
}

struct CommandPaletteRow: View {
    let action: PaletteAction
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .white : Color.white.opacity(0.85))
            }

            // Category badge
            Text(action.category)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(categoryColor(for: action.category).opacity(0.9))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(categoryColor(for: action.category).opacity(0.15))
                .cornerRadius(10)

            Spacer()

            if let shortcut = action.shortcut {
                Text(shortcut)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.3))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.3) : (isHovered ? Color.white.opacity(0.06) : Color.clear))
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}
