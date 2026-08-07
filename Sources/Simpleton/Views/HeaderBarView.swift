// Sources/Simpleton/Views/HeaderBarView.swift
import AppKit
import SwiftUI

/// The Slack-style window header: a profile/workspace switcher on the left, a center "omnibox"
/// (search-or-run) that opens the command palette, and quick-action buttons + an overflow menu on
/// the right. Themed to match the sidebar so the whole top strip reads as one colored chrome.
/// Hosted at the top of `TabContainerController`'s content with `fullSizeContentView`, so it spans
/// the full width under the traffic lights.
struct HeaderBarView: View {
    @ObservedObject var registry: PanelRegistry
    @ObservedObject private var themeSettings = ThemeSettings.shared
    @ObservedObject var model: HeaderModel

    /// Route a no-argument AppDelegate menu selector through the responder chain.
    private func fire(_ selector: String) {
        NSApp.sendAction(Selector((selector)), to: nil, from: nil)
    }

    var body: some View {
        HStack(spacing: 8) {
            // Clear the traffic lights (they are hidden in full screen, so collapse the reservation).
            Color.clear.frame(width: model.isFullScreen ? 6 : 70)

            profileSwitcher

            Spacer(minLength: 10)
            omnibox
            Spacer(minLength: 10)

            HeaderIconButton(icon: "plus", help: "New Tab  ⌘T") { fire("newTab") }
            HeaderIconButton(icon: "rectangle.split.2x1", help: "Split Right  ⌘D") { fire("splitRight") }
            HeaderIconButton(icon: "bolt.fill", help: "Quick Connect  ⌘K") { fire("showQuickConnect") }
            HeaderIconButton(icon: "sparkles", help: "AI Assistant  ⇧⌘A") {
                NotificationCenter.default.post(name: .simpletonToggleAIChat, object: nil)
            }
            overflowMenu
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .themedHeader(DT.surface)
        .overlay(
            Rectangle().fill(.black.opacity(0.18)).frame(height: 1),
            alignment: .bottom)
    }

    // MARK: - Left: profile / workspace switcher

    private var profileSwitcher: some View {
        Menu {
            Section("Workspaces") {
                ForEach(registry.profiles) { profile in
                    Button {
                        registry.activateProfile(profile)
                    } label: {
                        if profile.id == registry.activeProfile.id {
                            Label(profile.name, systemImage: "checkmark")
                        } else {
                            Text(profile.name)
                        }
                    }
                }
            }
            Divider()
            Button("Manage Workspaces…") { fire("showPreferences") }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 11))
                    .foregroundColor(themeSettings.accent)
                Text(registry.activeProfile.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DT.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(DT.textTertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .background(DT.hover.opacity(0.35), in: .rect(cornerRadius: 7, style: .continuous))
    }

    // MARK: - Center: omnibox

    private var omnibox: some View {
        Button {
            fire("showCommandPalette")
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(DT.textMuted)
                Text("Search connections or run a command…")
                    .font(.system(size: 12))
                    .foregroundColor(DT.textMuted)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("⇧⌘P")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DT.textFaint)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(DT.elevated, in: .rect(cornerRadius: 4, style: .continuous))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(DT.base.opacity(0.55), in: Capsule())
            .overlay(Capsule().strokeBorder(DT.border, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 520)
    }

    // MARK: - Right: overflow

    private var overflowMenu: some View {
        Menu {
            Button("New Window") { fire("createNewWindow") }
            Button("New Connection…") { fire("showNewConnection") }
            Button("Command Palette…") { fire("showCommandPalette") }
            Divider()
            Button("Settings…") { fire("showPreferences") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DT.textSecondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// A themed 30×30 icon button for the header's right-side action cluster.
struct HeaderIconButton: View {
    let icon: String
    let help: String
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(hovered ? DT.textPrimary : DT.textSecondary)
                .frame(width: 30, height: 30)
                .background(
                    hovered ? DT.hover : Color.clear,
                    in: .rect(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { h in withAnimation(DT.hoverAnimation) { hovered = h } }
    }
}

/// Lightweight observable the container updates so the header can show the active pane's title
/// without threading callbacks through SwiftUI.
final class HeaderModel: ObservableObject {
    @Published var title: String = "Simpleton"
    /// True while the window is in native full screen. The traffic lights are hidden there, so the
    /// header collapses the space it reserves for them (otherwise the workspace switcher stays
    /// indented ~70px behind nothing).
    @Published var isFullScreen: Bool = false

    private var observers: [NSObjectProtocol] = []
    init() {
        let nc = NotificationCenter.default
        observers.append(
            nc.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: nil, queue: .main) {
                [weak self] _ in self?.isFullScreen = true
            })
        observers.append(
            nc.addObserver(forName: NSWindow.didExitFullScreenNotification, object: nil, queue: .main) {
                [weak self] _ in self?.isFullScreen = false
            })
    }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
}
