// Sources/Simpleton/Panels/ClientPanelScaffold.swift
import SwiftUI

/// Availability of a client panel's backing service, driving what the scaffold shows in its body.
enum ClientAvailability {
    /// First load in progress — show a spinner.
    case loading
    /// Service reachable — show the panel's own `content`.
    case ready
    /// Service unavailable (missing CLI, not running, unreachable) — show an empty state with an
    /// optional action button. Fields map straight onto `PanelEmptyStateView`.
    case unavailable(
        icon: String, title: String, message: String, actionLabel: String? = nil,
        action: (() -> Void)? = nil)
}

/// Shared chrome for tool/client panels: an uppercase title, a refresh button (spinner while a
/// manual refresh runs), a `ThemedDivider`, and a body that switches on `availability`. Owns the
/// auto-refresh timer so consumers only supply their data + an `onRefresh` closure. Extracted from
/// the original Docker/Processes panels so every client panel shares one look and lifecycle.
struct ClientPanelScaffold<Content: View>: View {
    let title: String
    let availability: ClientAvailability
    let autoRefresh: TimeInterval?
    let onRefresh: () async -> Void
    @ViewBuilder let content: () -> Content

    @ObservedObject private var themeSettings = ThemeSettings.shared
    @State private var timer: Timer?
    @State private var isRefreshing = false

    init(
        title: String,
        availability: ClientAvailability,
        autoRefresh: TimeInterval?,
        onRefresh: @escaping () async -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.availability = availability
        self.autoRefresh = autoRefresh
        self.onRefresh = onRefresh
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ThemedDivider()
            body(for: availability)
        }
        .onAppear {
            Task { await onRefresh() }
            if let interval = autoRefresh {
                timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                    Task { @MainActor in await onRefresh() }
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.5)
                .foregroundColor(DT.textPrimary)
            Spacer()
            Button {
                Task {
                    isRefreshing = true
                    await onRefresh()
                    isRefreshing = false
                }
            } label: {
                if isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise").foregroundColor(DT.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func body(for availability: ClientAvailability) -> some View {
        switch availability {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            content()
        case .unavailable(let icon, let title, let message, let actionLabel, let action):
            PanelEmptyStateView(
                icon: icon, title: title, message: message, actionLabel: actionLabel, action: action)
        }
    }
}
