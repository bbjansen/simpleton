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
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = NSColor(white: 0.12, alpha: 0.98)
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
            panel.setFrameOrigin(NSPoint(x: windowFrame.midX - 250, y: windowFrame.midY + 50))
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
            HStack(spacing: 8) {
                Text(">")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14, design: .monospaced))
                TextField("Type a command...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .onSubmit { selectCurrent() }
            }
            .padding(14)
            .background(Color.white.opacity(0.05))

            Divider().background(Color.white.opacity(0.1))

            // Results
            ScrollViewReader { proxy in
                List(Array(filtered.enumerated()), id: \.element.id) { index, action in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(action.title)
                                .font(.system(size: 13, weight: index == selectedIndex ? .semibold : .regular))
                                .foregroundColor(index == selectedIndex ? .white : .primary)
                        }
                        Spacer()
                        if let shortcut = action.shortcut {
                            Text(shortcut)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.3))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(3)
                        }
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(index == selectedIndex ? Color.accentColor.opacity(0.2) : Color.clear)
                    .cornerRadius(6)
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
            Divider().background(Color.white.opacity(0.1))
            HStack(spacing: 16) {
                Text("↑↓ navigate")
                Text("↵ select")
                Text("esc close")
            }
            .font(.system(size: 10))
            .foregroundColor(Color.white.opacity(0.3))
            .padding(8)
        }
        .frame(width: 500, height: 400)
        .background(Color(nsColor: NSColor(white: 0.12, alpha: 1)))
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

    private func selectCurrent() {
        let items = filtered
        guard selectedIndex < items.count else { return }
        onSelect(items[selectedIndex])
    }
}
