// Sources/Simpleton/Views/ChatViews/ChatHeaderView.swift
import SwiftUI

struct ChatHeaderView: View {
    @Binding var autopilotMode: AutopilotMode
    @Binding var showAutopilotConfirm: Bool
    @Binding var watchActive: Bool
    var onDismiss: (() -> Void)?
    // Observe the theme so this bar's `DT.surface` background re-renders on a live theme switch —
    // its @Binding inputs don't change, so without this SwiftUI would skip its body and the header
    // would stay on the previous theme's color while the rest of the AI panel flips.
    @ObservedObject private var themeSettings = ThemeSettings.shared

    var body: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundColor(DT.accent)
            Text("AI Assistant")
                .font(.system(size: 13, weight: .semibold))
            Spacer()

            // Watch toggle
            Button(action: {
                watchActive.toggle()
            }) {
                HStack(spacing: 3) {
                    Image(systemName: watchActive ? "eye.fill" : "eye")
                        .font(.system(size: 9))
                    Text("Watch")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(watchActive ? .white : DT.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(watchActive ? DT.accentBlue : Color.clear)
                .cornerRadius(4)
            }
            .buttonStyle(.plain)

            // Autopilot toggle
            Button(action: {
                switch autopilotMode {
                case .off:
                    showAutopilotConfirm = true
                case .safe:
                    autopilotMode = .full
                case .full:
                    autopilotMode = .off
                }
            }) {
                Text(autopilotLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(autopilotMode == .off ? DT.textSecondary : .white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(autopilotBackground)
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .alert("Enable Safe Autopilot?", isPresented: $showAutopilotConfirm) {
                Button("Enable", role: .destructive) { autopilotMode = .safe }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Safe mode auto-approves read-only commands (ls, cat, grep, git status, etc.). Destructive commands still require your approval. Tap again to switch to full autopilot."
                )
            }

            if let dismiss = onDismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DT.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(DT.surface)
    }

    private var autopilotLabel: String {
        switch autopilotMode {
        case .off: return "Autopilot"
        case .safe: return "Autopilot SAFE"
        case .full: return "Autopilot FULL"
        }
    }

    private var autopilotBackground: Color {
        switch autopilotMode {
        case .off: return .clear
        case .safe: return DT.accentAmber.opacity(0.7)
        case .full: return DT.accentAmber
        }
    }
}
