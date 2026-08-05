// Sources/Simpleton/Views/CommandPalettePanel.swift
import AppKit
import SimpletonCore
import SwiftUI

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

        // Create the panel once and reuse it; update content view with fresh actions each show
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
            newPanel.backgroundColor = .clear
            newPanel.isOpaque = false
            newPanel.hasShadow = true
            newPanel.becomesKeyOnlyIfNeeded = false
            // NOTE: do NOT `setValue(_, forKey: "shadow")` here — NSWindow is not KVC-compliant for
            // "shadow", so it raises NSUnknownKeyException. AppKit's run loop swallows exceptions
            // thrown during a menu action, so instead of crashing it silently aborted the palette
            // (the panel never appeared). Window shadow is already enabled via `hasShadow = true`.

            self.panel = newPanel
            // Dismiss when the panel loses focus (user clicks away) — Spotlight/Raycast behaviour.
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: newPanel, queue: .main
            ) { [weak self] _ in
                self?.dismiss()
            }
        }

        guard let panel = panel else { return }

        // Rebuild content view with current actions each time so the list is fresh
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

        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        // Fade out, then orderOut (hides without deallocating, avoiding use-after-free in AppKit
        // window animation blocks). Guard on isVisible so the resign-key observer can't re-enter.
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
            // Search field — large, no border, bottom divider only
            HStack(spacing: 10) {
                Image(systemName: "command")
                    .foregroundColor(DT.textMuted)
                    .font(.system(size: 14, weight: .medium))
                AutoFocusTextField(
                    text: $query, placeholder: "Type a command...",
                    onSubmit: selectCurrent,
                    onMoveUp: { if selectedIndex > 0 { selectedIndex -= 1 } },
                    onMoveDown: { if selectedIndex < filtered.count - 1 { selectedIndex += 1 } },
                    onCancel: onDismiss
                )
                .font(.system(size: 18))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            Rectangle()
                .fill(DT.border.opacity(0.5))
                .frame(height: 0.5)

            // Results
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, action in
                            CommandPaletteRow(action: action, isSelected: index == selectedIndex)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(action) }
                                .id(action.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .onChange(of: selectedIndex) { _, newIndex in
                    if newIndex < filtered.count {
                        proxy.scrollTo(filtered[newIndex].id, anchor: .center)
                    }
                }
            }

            // Footer
            Rectangle()
                .fill(DT.border.opacity(0.5))
                .frame(height: 0.5)
            HStack(spacing: 20) {
                footerHint(keys: "\u{2191}\u{2193}", label: "navigate")
                footerHint(keys: "\u{21A9}", label: "select")
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
            withAnimation(.easeOut(duration: 0.2)) {
                isAppeared = true
            }
        }
        .onChange(of: query) { selectedIndex = 0 }
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

    private func selectCurrent() {
        let items = filtered
        guard selectedIndex < items.count else { return }
        onSelect(items[selectedIndex])
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
                    .foregroundColor(isSelected ? DT.textPrimary : DT.textSecondary)
            }

            // Category badge — colored pill
            Text(action.category)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(DT.categoryColor(for: action.category).opacity(0.9))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DT.categoryColor(for: action.category).opacity(0.15))
                .cornerRadius(DT.radiusPill)

            Spacer()

            if let shortcut = action.shortcut {
                Text(shortcut)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(DT.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(DT.elevated)
                    .cornerRadius(4)
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
