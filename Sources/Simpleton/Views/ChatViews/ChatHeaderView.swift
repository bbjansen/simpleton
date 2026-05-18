// Sources/Simpleton/Views/ChatViews/ChatHeaderView.swift
import SwiftUI

struct ChatHeaderView: View {
    @Binding var autopilotEnabled: Bool
    @Binding var showAutopilotConfirm: Bool
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundColor(.purple)
            Text("AI Assistant")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button(action: {
                if autopilotEnabled {
                    autopilotEnabled = false
                } else {
                    showAutopilotConfirm = true
                }
            }) {
                Text(autopilotEnabled ? "Autopilot ON" : "Autopilot")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(autopilotEnabled ? .white : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(autopilotEnabled ? Color.orange : Color.clear)
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .alert("Enable Autopilot?", isPresented: $showAutopilotConfirm) {
                Button("Enable", role: .destructive) { autopilotEnabled = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The AI will execute commands in your terminal without asking for approval. It can run any shell command, modify files, and control processes.")
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
}
