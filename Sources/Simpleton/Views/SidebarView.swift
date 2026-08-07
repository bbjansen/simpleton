// Sources/Simpleton/Views/SidebarView.swift
import AppKit
import SimpletonCore
import SwiftUI

struct SidebarView: View {
    let bookmarkStore: BookmarkStore
    let sshConfigWatcher: SSHConfigWatcher?
    let onConnect: (Bookmark) -> Void
    let onNewConnection: () -> Void

    @State private var pinned: [Bookmark] = []
    @State private var recent: [Bookmark] = []
    @State private var sshConfigEntries: [SSHConfigEntry] = []
    @State private var smartGroups: [SmartGroup] = []
    @ObservedObject private var themeSettings = ThemeSettings.shared

    private var hasNoConnections: Bool {
        pinned.isEmpty && recent.isEmpty && sshConfigEntries.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if hasNoConnections {
                emptyState
            } else {
                normalSidebar
            }

            Rectangle()
                .fill(DT.border.opacity(0.5))
                .frame(height: 0.5)

            // Add Connection — pinned at the bottom of the sidebar.
            addConnectionButton
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
        .themedGlass(DT.surface)  // theme-colored vibrancy — fully the theme's color, glassy sheen
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .simpletonBookmarksChanged)) { _ in refresh() }
    }

    private var allBookmarks: [Bookmark] {
        pinned + recent
    }

    // Ghost-style "Add Connection" action, pinned at the bottom of the sidebar.
    private var addConnectionButton: some View {
        Button(action: onNewConnection) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 13))
                Text("Add Connection")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(DT.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: DT.radiusCard)
                    .stroke(DT.border.opacity(0.5), lineWidth: 1)
            )
            .cornerRadius(DT.radiusCard)
            .contentShape(Rectangle())
        }
        .buttonStyle(GhostButtonStyle())
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "network.slash")
                .font(.system(size: 28))
                .foregroundColor(DT.textFaint)
            Text("No connections yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DT.textMuted)
            Text("Add one or import from\n~/.ssh/config")
                .font(.system(size: 11))
                .foregroundColor(DT.textFaint)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var normalSidebar: some View {
        List {
            if !pinned.isEmpty {
                Section {
                    ForEach(pinned) { bookmark in
                        SidebarRow(bookmark: bookmark, onConnect: onConnect)
                    }
                } header: {
                    SidebarSectionHeader(title: "Pinned")
                }
            }

            if !recent.isEmpty {
                Section {
                    ForEach(recent.prefix(10)) { bookmark in
                        SidebarRow(bookmark: bookmark, onConnect: onConnect)
                    }
                } header: {
                    SidebarSectionHeader(title: "Recent")
                }
            }

            // Show ~/.ssh/config entries that aren't already bookmarks
            let importedHosts = Set(allBookmarks.compactMap(\.sshConfigHost))
            let unimported = sshConfigEntries.filter { !importedHosts.contains($0.hostAlias) }
            if !unimported.isEmpty {
                if !pinned.isEmpty || !recent.isEmpty {
                    Rectangle()
                        .fill(DT.border.opacity(0.3))
                        .frame(height: 0.5)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                Section {
                    ForEach(unimported, id: \.hostAlias) { entry in
                        SSHConfigRow(entry: entry, onConnect: connectSSHConfigEntry)
                    }
                } header: {
                    SidebarSectionHeader(title: "SSH Config")
                }
            }

            if !smartGroups.isEmpty {
                Section {
                    ForEach(smartGroups) { group in
                        Label(group.name, systemImage: "folder")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: group.color) ?? .secondary)
                    }
                } header: {
                    SidebarSectionHeader(title: "Smart Groups")
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .tint(themeSettings.accent)
        .environment(\.defaultMinListRowHeight, 34)
    }

    private func connectSSHConfigEntry(_ entry: SSHConfigEntry) {
        let bookmark = entry.toBookmark()
        onConnect(bookmark)
    }

    private func refresh() {
        Task {
            pinned = await bookmarkStore.pinnedBookmarks()
            recent = await bookmarkStore.allBookmarks().filter { !$0.pinned }
        }
        sshConfigEntries = sshConfigWatcher?.concreteEntries ?? []
    }
}

// MARK: - Ghost Button Style

struct GhostButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: DT.radiusCard)
                    .fill(isHovered ? DT.hover : Color.clear)
            )
            .onHover { hovering in
                withAnimation(DT.hoverAnimation) {
                    isHovered = hovering
                }
            }
    }
}

// MARK: - Section Header

struct SidebarSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(1.5)
            .foregroundColor(DT.textPrimary)
            .padding(.bottom, 2)
    }
}

// MARK: - Sidebar Row (Bookmark)

struct SidebarRow: View {
    let bookmark: Bookmark
    let onConnect: (Bookmark) -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: { onConnect(bookmark) }) {
            HStack(spacing: 8) {
                // Connection status dot
                Circle()
                    .fill(DT.textFaint)
                    .frame(width: 6, height: 6)

                Image(systemName: bookmark.pinned ? "star.fill" : "network")
                    .font(.system(size: 10))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(bookmark.pinned ? DT.accentAmber : DT.textMuted)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(bookmark.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isHovered ? DT.textPrimary : DT.textSecondary)
                        .lineLimit(1)
                    Text(bookmark.host)
                        .font(DT.monoFont(size: 10))
                        .foregroundColor(DT.textMuted)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: DT.radiusButton, style: .continuous)
                    .fill(isHovered ? DT.hover : Color.clear)
            )
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DT.hoverAnimation) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - SSH Config Row

struct SSHConfigRow: View {
    let entry: SSHConfigEntry
    let onConnect: (SSHConfigEntry) -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: { onConnect(entry) }) {
            HStack(spacing: 8) {
                Circle()
                    .fill(DT.textFaint)
                    .frame(width: 6, height: 6)

                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                    .foregroundColor(DT.accentBlue.opacity(0.7))
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.hostAlias)
                        .font(.system(size: 12))
                        .foregroundColor(isHovered ? DT.textPrimary : DT.textSecondary)
                        .lineLimit(1)
                    Text(entry.hostname ?? entry.hostAlias)
                        .font(DT.monoFont(size: 10))
                        .foregroundColor(DT.textMuted)
                        .lineLimit(1)
                }
                Spacer()

                // "imported" badge
                Text("imported")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(DT.textFaint)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(DT.textFaint.opacity(0.15))
                    .cornerRadius(DT.radiusPill)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: DT.radiusButton, style: .continuous)
                    .fill(isHovered ? DT.hover : Color.clear)
            )
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DT.hoverAnimation) {
                isHovered = hovering
            }
        }
    }
}

// Color from hex string for SwiftUI
extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let rgb = UInt64(h, radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
