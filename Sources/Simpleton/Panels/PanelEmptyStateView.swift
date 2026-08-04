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
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            if let label = actionLabel, let action {
                Button(label, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
