import AppKit
// Sources/Simpleton/Panels/FileBrowserPanelView.swift
import SwiftUI

struct FileBrowserEntry: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let isDirectory: Bool
}

struct FileBrowserPanelView: View {
    let onInsert: (String) -> Void
    let currentPaneProvider: () -> PaneController?

    @ObservedObject private var themeSettings = ThemeSettings.shared

    @State private var currentURL: URL = FileManager.default.homeDirectoryForCurrentUser
    @State private var entries: [FileBrowserEntry] = []

    private var breadcrumbs: [URL] {
        var parts: [URL] = []
        var url = currentURL
        while url.path != "/" {
            parts.insert(url, at: 0)
            url = url.deletingLastPathComponent()
        }
        parts.insert(URL(fileURLWithPath: "/"), at: 0)
        return parts
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(breadcrumbs, id: \.path) { url in
                        Button(url.path == "/" ? "/" : url.lastPathComponent) {
                            navigate(to: url)
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(themeSettings.accent)
                        if url.path != breadcrumbs.last?.path {
                            Text(">")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            Divider()
            if entries.isEmpty {
                PanelEmptyStateView(
                    icon: "folder",
                    title: "Empty folder",
                    message: currentURL.path
                )
            } else {
                List(entries) { entry in
                    HStack(spacing: 6) {
                        Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                            .foregroundStyle(entry.isDirectory ? themeSettings.accent : Color.secondary)
                        Text(entry.name)
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(entry.isDirectory ? .semibold : .regular)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            if entry.isDirectory { navigate(to: entry.url) }
                        }
                    )
                    .onTapGesture {
                        onInsert(entry.url.path)
                    }
                }
                .listStyle(.plain)
            }
        }
        .onAppear { syncCWD() }
    }

    private func syncCWD() {
        if let cwd = currentPaneProvider()?.currentDirectory {
            currentURL = URL(fileURLWithPath: cwd)
        }
        loadEntries()
    }

    private func navigate(to url: URL) {
        currentURL = url
        loadEntries()
    }

    private func loadEntries() {
        let fm = FileManager.default
        guard
            let items = try? fm.contentsOfDirectory(
                at: currentURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            entries = []
            return
        }
        entries = items.compactMap { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return FileBrowserEntry(name: url.lastPathComponent, url: url, isDirectory: isDir)
        }
        .sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}
