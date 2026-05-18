// Sources/Simpleton/Views/AgentExecutionBubble.swift
import SwiftUI

struct AgentExecutionBubble: View {
    let cmd: String
    let explanation: String
    let status: BubbleStatus
    var output: String = ""
    var onAllow: (() -> Void)?
    var onSkip: (() -> Void)?
    var onStop: (() -> Void)?

    @State private var showOutput = false

    enum BubbleStatus {
        case waitingApproval, running, done, failed, skipped
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                statusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(cmd)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    if !explanation.isEmpty {
                        Text(explanation)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if !output.isEmpty {
                    Button(action: { showOutput.toggle() }) {
                        Text(showOutput ? "Hide" : "Output")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if case .waitingApproval = status {
                HStack(spacing: 8) {
                    approvalButton("Allow", color: .green, action: onAllow)
                    approvalButton("Skip", color: .orange, action: onSkip)
                    approvalButton("Stop", color: .red, action: onStop)
                }
            }

            if showOutput && !output.isEmpty {
                Text(output)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(nsColor: NSColor(white: 0.7, alpha: 1)))
                    .padding(8)
                    .background(Color(nsColor: NSColor(white: 0.05, alpha: 1)))
                    .cornerRadius(6)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .background(Color(nsColor: NSColor(white: 0.1, alpha: 1)))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(statusBorderColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .waitingApproval:
            Image(systemName: "questionmark.circle.fill").foregroundColor(.orange)
        case .running:
            ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundColor(.red)
        case .skipped:
            Image(systemName: "forward.circle.fill").foregroundColor(.secondary)
        }
    }

    private var statusBorderColor: Color {
        switch status {
        case .waitingApproval: return .orange.opacity(0.5)
        case .running: return .purple.opacity(0.5)
        case .done: return .green.opacity(0.3)
        case .failed: return .red.opacity(0.5)
        case .skipped: return Color(nsColor: NSColor(white: 0.25, alpha: 1))
        }
    }

    private func approvalButton(_ label: String, color: Color, action: (() -> Void)?) -> some View {
        Button(action: { action?() }) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(color.opacity(0.15))
                .foregroundColor(color)
                .cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(color.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
