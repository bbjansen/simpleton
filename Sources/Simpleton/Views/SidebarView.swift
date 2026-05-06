// Sources/Simpleton/Views/SidebarView.swift
import AppKit
import SwiftUI
import SimpletonCore

struct SidebarView: View {
    let bookmarkStore: BookmarkStore
    let sshConfigWatcher: SSHConfigWatcher?
    let onConnect: (Bookmark) -> Void
    let onNewConnection: () -> Void

    @State private var pinned: [Bookmark] = []
    @State private var recent: [Bookmark] = []
    @State private var sshConfigEntries: [SSHConfigEntry] = []
    @State private var smartGroups: [SmartGroup] = []
    @State private var searchQuery = ""

    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                TextField("Search connections...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(8)
            .background(Color.white.opacity(0.05))

            Divider().background(Color.white.opacity(0.1))

            if !searchQuery.isEmpty {
                searchResults
            } else {
                normalSidebar
            }

            Divider().background(Color.white.opacity(0.1))

            // Add connection button
            Button(action: onNewConnection) {
                Label("Add Connection", systemImage: "plus")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .padding(8)
        }
        .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
        .background(Color(nsColor: NSColor(white: 0.1, alpha: 1)))
        .onAppear { refresh() }
    }

    private var allBookmarks: [Bookmark] {
        pinned + recent
    }

    private var normalSidebar: some View {
        List {
            if !pinned.isEmpty {
                Section("Pinned") {
                    ForEach(pinned) { bookmark in
                        SidebarRow(bookmark: bookmark, onConnect: onConnect)
                    }
                }
            }

            if !recent.isEmpty {
                Section("Recent") {
                    ForEach(recent.prefix(10)) { bookmark in
                        SidebarRow(bookmark: bookmark, onConnect: onConnect)
                    }
                }
            }

            // Show ~/.ssh/config entries that aren't already bookmarks
            let importedHosts = Set(allBookmarks.compactMap(\.sshConfigHost))
            let unimported = sshConfigEntries.filter { !importedHosts.contains($0.hostAlias) }
            if !unimported.isEmpty {
                Section("From ~/.ssh/config") {
                    ForEach(unimported, id: \.hostAlias) { entry in
                        Button(action: { connectSSHConfigEntry(entry) }) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.blue.opacity(0.5))
                                    .frame(width: 6, height: 6)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.hostAlias)
                                        .font(.system(size: 12))
                                        .lineLimit(1)
                                    Text(entry.hostname ?? entry.hostAlias)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !smartGroups.isEmpty {
                Section("Smart Groups") {
                    ForEach(smartGroups) { group in
                        Label(group.name, systemImage: "folder")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: group.color) ?? .secondary)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var searchResults: some View {
        let q = searchQuery.lowercased()
        let matchingBookmarks = allBookmarks.filter {
            $0.name.lowercased().contains(q) || $0.host.lowercased().contains(q)
        }
        let matchingSSH = sshConfigEntries.filter {
            $0.hostAlias.lowercased().contains(q) || ($0.hostname?.lowercased().contains(q) ?? false)
        }
        return List {
            ForEach(matchingBookmarks) { bookmark in
                SidebarRow(bookmark: bookmark, onConnect: onConnect)
            }
            ForEach(matchingSSH, id: \.hostAlias) { entry in
                Button(action: { connectSSHConfigEntry(entry) }) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.blue.opacity(0.5)).frame(width: 6, height: 6)
                        Text(entry.hostAlias).font(.system(size: 12)).lineLimit(1)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
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

struct SidebarRow: View {
    let bookmark: Bookmark
    let onConnect: (Bookmark) -> Void

    var body: some View {
        Button(action: { onConnect(bookmark) }) {
            HStack(spacing: 6) {
                Circle()
                    .fill(bookmark.pinned ? Color.green : Color.gray.opacity(0.5))
                    .frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(bookmark.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Text(bookmark.host)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
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
