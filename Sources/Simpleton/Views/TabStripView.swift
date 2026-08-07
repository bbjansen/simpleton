// Sources/Simpleton/Views/TabStripView.swift
import SwiftUI

/// The custom in-app tab strip, replacing macOS native window tabbing. Rendered as a themed row
/// directly below the header in every tab's container, driven by the window's shared `TabManager`,
/// so it looks continuous when the active container is swapped in. Hidden when there is a single tab
/// (Terminal.app behavior).
struct TabStripView: View {
    @ObservedObject var manager: TabManager
    @ObservedObject private var themeSettings = ThemeSettings.shared

    /// Strip height. Kept in sync with `TabContainerController.tabStripHeight`.
    static let height: CGFloat = 32

    var body: some View {
        if manager.tabs.count > 1 {
            HStack(spacing: 4) {
                ForEach(manager.tabs) { tab in
                    TabPill(
                        title: tab.title,
                        isActive: tab.id == manager.activeTabID,
                        accent: themeSettings.accent,
                        onSelect: { manager.activate(tab.id) },
                        onClose: { manager.close(tab.id) }
                    )
                }
                Spacer(minLength: 4)
                NewTabButton {
                    NSApp.sendAction(Selector(("newTab")), to: nil, from: nil)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: Self.height)
            .themedHeader(DT.surface)
            .overlay(
                Rectangle().fill(.black.opacity(0.18)).frame(height: 1),
                alignment: .bottom)
        }
    }
}

/// A single tab pill: title + a close "×" that appears on hover or when the tab is active. The
/// active pill is tinted with the theme accent; inactive pills stay grayscale and light up on hover.
private struct TabPill: View {
    let title: String
    let isActive: Bool
    let accent: Color
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var hovered = false

    private var background: Color {
        if isActive { return accent.opacity(0.22) }
        return hovered ? DT.hover : Color.clear
    }

    private var titleColor: Color {
        isActive ? DT.textPrimary : DT.textSecondary
    }

    private var showsClose: Bool { isActive || hovered }

    var body: some View {
        HStack(spacing: 6) {
            Text(title.isEmpty ? "Terminal" : title)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundColor(titleColor)
                .lineLimit(1)
                .truncationMode(.tail)

            // Reserve the close-button footprint so the pill width doesn't jump on hover.
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(hovered ? DT.textPrimary : DT.textTertiary)
                    .frame(width: 14, height: 14)
                    .background(
                        hovered ? DT.selected : Color.clear,
                        in: .rect(cornerRadius: 4, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(showsClose ? 1 : 0)
            .allowsHitTesting(showsClose)
            .help("Close Tab  ⌘W")
        }
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .frame(height: 24)
        .frame(minWidth: 90, maxWidth: 200)
        .background(background, in: .rect(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(isActive ? accent.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { h in withAnimation(DT.hoverAnimation) { hovered = h } }
    }
}

/// The trailing "＋" that opens a new tab.
private struct NewTabButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(hovered ? DT.textPrimary : DT.textSecondary)
                .frame(width: 24, height: 24)
                .background(
                    hovered ? DT.hover : Color.clear,
                    in: .rect(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("New Tab  ⌘T")
        .onHover { h in withAnimation(DT.hoverAnimation) { hovered = h } }
    }
}
