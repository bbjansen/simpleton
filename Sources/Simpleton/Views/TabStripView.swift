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
            HStack(spacing: 5) {
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

/// A single tab pill. The active pill reads as a raised, accent-lit surface: an elevated fill, a
/// hairline that catches light, a soft accent wash, and a short accent bar along the top edge so the
/// focused tab is obvious at a glance. Inactive pills stay flat and grayscale, lighting to a subtle
/// fill on hover. The close "×" is only present on the active or hovered pill.
private struct TabPill: View {
    let title: String
    let isActive: Bool
    let accent: Color
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var hovered = false

    private var showsClose: Bool { isActive || hovered }

    // Fill: active → an elevated surface tinted by the accent so it lifts off the strip; inactive →
    // clear, warming to the theme hover fill under the cursor.
    @ViewBuilder private var fill: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        if isActive {
            ZStack {
                shape.fill(DT.elevated)
                shape.fill(accent.opacity(0.18))
            }
        } else {
            shape.fill(hovered ? DT.hover : Color.clear)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title.isEmpty ? "Terminal" : title)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? DT.textPrimary : DT.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)

            // Reserve the close-button footprint so the pill width doesn't jump on hover.
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(hovered ? DT.textPrimary : DT.textTertiary)
                    .frame(width: 15, height: 15)
                    .background(
                        hovered ? DT.selected : Color.clear,
                        in: .rect(cornerRadius: 4, style: .continuous)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(showsClose ? 1 : 0)
            .allowsHitTesting(showsClose)
            .help("Close Tab  ⌘W")
        }
        .padding(.leading, 11)
        .padding(.trailing, 5)
        .frame(height: 25)
        .frame(minWidth: 96, maxWidth: 200)
        .background(fill)
        .overlay(
            // Hairline: a bright accent edge on the active pill, an invisible edge otherwise.
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(isActive ? accent.opacity(0.55) : Color.clear, lineWidth: 1)
        )
        .overlay(alignment: .top) {
            // Accent bar hugging the top edge — the signature "this tab is focused" indicator.
            if isActive {
                Capsule(style: .continuous)
                    .fill(accent)
                    .frame(width: 22, height: 2.5)
                    .padding(.top, 2)
                    .shadow(color: accent.opacity(0.6), radius: 3, y: 0)
            }
        }
        .shadow(color: .black.opacity(isActive ? 0.22 : 0), radius: 4, y: 1)
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
                .frame(width: 25, height: 25)
                .background(
                    hovered ? DT.hover : Color.clear,
                    in: .rect(cornerRadius: 7, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("New Tab  ⌘T")
        .onHover { h in withAnimation(DT.hoverAnimation) { hovered = h } }
    }
}
