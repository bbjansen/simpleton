import AppKit
import SimpletonCore
// Sources/Simpleton/Panels/SSHTunnelsPanelView.swift
import SwiftUI

struct TunnelEntry: Identifiable {
    let id = UUID()
    let localPort: Int
    let remoteHost: String
    let remotePort: Int
    let paneName: String
}

struct SSHTunnelsPanelView: View {
    @ObservedObject private var themeSettings = ThemeSettings.shared

    let tabContainerProvider: () -> TabContainerController?
    let bookmarkStore: BookmarkStore?

    @State private var tunnels: [TunnelEntry] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SSH TUNNELS")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(DT.textPrimary)
                Spacer()
                Button {
                    loadTunnels()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(DT.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            ThemedDivider()
            if tunnels.isEmpty {
                PanelEmptyStateView(
                    icon: "network",
                    title: "No active tunnels",
                    message: "SSH port forwards will appear here when active connections have tunnels configured."
                )
            } else {
                List(tunnels) { tunnel in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("localhost:\(tunnel.localPort) → \(tunnel.remoteHost):\(tunnel.remotePort)")
                            .font(DT.monoFont(size: 11))
                            .foregroundColor(DT.textPrimary)
                        Text(tunnel.paneName)
                            .font(.caption2)
                            .foregroundColor(DT.textTertiary)
                    }
                    .listRowBackground(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("localhost:\(tunnel.localPort)", forType: .string)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .themedGlass(DT.surface)
        .onAppear { loadTunnels() }
        .onReceive(NotificationCenter.default.publisher(for: .simpletonWindowClosed)) { _ in
            loadTunnels()
        }
        .onReceive(NotificationCenter.default.publisher(for: .simpletonSplitChanged)) { _ in
            loadTunnels()
        }
    }

    private func loadTunnels() {
        // Screenshot demo mode: show sample active tunnels (real sessions here are local, so the
        // panel would otherwise be empty). Gated by env; off in normal use.
        if ProcessInfo.processInfo.environment["SIMPLETON_SHOT_DEMO"] != nil {
            tunnels = [
                TunnelEntry(localPort: 8080, remoteHost: "localhost", remotePort: 80, paneName: "prod-web"),
                TunnelEntry(localPort: 5432, remoteHost: "db.internal", remotePort: 5432, paneName: "db-primary"),
                TunnelEntry(
                    localPort: 9090, remoteHost: "grafana.internal", remotePort: 3000, paneName: "staging-api"),
            ]
            return
        }
        guard let panes = tabContainerProvider()?.splitController.panes else {
            tunnels = []
            return
        }
        tunnels = panes.values.flatMap { pane -> [TunnelEntry] in
            guard case .ssh(let bookmarkID) = pane.connectionType,
                let bookmark = bookmarkStore?.bookmark(for: bookmarkID),
                !bookmark.portForwards.isEmpty
            else { return [] }
            let name = bookmark.name
            return bookmark.portForwards
                .filter { $0.direction == .local }
                .map { pf in
                    TunnelEntry(
                        localPort: pf.localPort,
                        remoteHost: pf.remoteHost,
                        remotePort: pf.remotePort,
                        paneName: name
                    )
                }
        }
        .sorted { $0.localPort < $1.localPort }
    }
}
