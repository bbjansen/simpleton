import AppKit
// Sources/Simpleton/Panels/PanelEmptyStateView.swift
import SwiftUI

/// Generic empty-state view used by panels whose dependency is absent.
struct PanelEmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(DT.textMuted)
            Text(title)
                .font(.headline)
                .foregroundColor(DT.textSecondary)
            Text(message)
                .font(.subheadline)
                .foregroundColor(DT.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            if let label = actionLabel, let action {
                Button(label, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(DT.accent)
                    .controlSize(.small)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
