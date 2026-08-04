// Sources/Simpleton/Views/ChatViews/ChatHeaderView.swift
import SwiftUI

struct ChatHeaderView: View {
    @Binding var autopilotMode: AutopilotMode
    @Binding var showAutopilotConfirm: Bool
    @Binding var watchActive: Bool
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundColor(.purple)
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
                .foregroundColor(watchActive ? .white : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(watchActive ? Color.blue : Color.clear)
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
                    .foregroundColor(autopilotMode == .off ? .secondary : .white)
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
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color(nsColor: NSColor(white: 0.08, alpha: 1)))
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
        case .safe: return .yellow.opacity(0.7)
        case .full: return .orange
        }
    }
}
