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
    // Repaint this transcript bubble's `DT.*` tints on a live theme switch (its inputs don't change).
    @ObservedObject private var themeSettings = ThemeSettings.shared

    enum BubbleStatus {
        case waitingApproval, running, done, failed, skipped
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                statusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(cmd)
                        .font(DT.monoFont(size: 11))
                        .foregroundColor(DT.textPrimary)
                        .lineLimit(2)
                    if !explanation.isEmpty {
                        Text(explanation)
                            .font(.system(size: 10))
                            .foregroundColor(DT.textSecondary)
                    }
                }
                Spacer()
                if !output.isEmpty {
                    Button(action: { showOutput.toggle() }) {
                        Text(showOutput ? "Hide" : "Output")
                            .font(.system(size: 9))
                            .foregroundColor(DT.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if case .waitingApproval = status {
                HStack(spacing: 8) {
                    approvalButton("Allow", color: DT.accentGreen, action: onAllow)
                    approvalButton("Skip", color: DT.accentAmber, action: onSkip)
                    approvalButton("Stop", color: DT.accentRed, action: onStop)
                }
            }

            if showOutput && !output.isEmpty {
                Text(output)
                    .font(DT.monoFont(size: 10))
                    .foregroundColor(DT.textSecondary)
                    .padding(8)
                    .background(DT.base)
                    .cornerRadius(6)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .background(DT.elevated)
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
            Image(systemName: "questionmark.circle.fill").foregroundColor(DT.accentAmber)
        case .running:
            ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundColor(DT.accentGreen)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundColor(DT.accentRed)
        case .skipped:
            Image(systemName: "forward.circle.fill").foregroundColor(DT.textSecondary)
        }
    }

    private var statusBorderColor: Color {
        switch status {
        case .waitingApproval: return DT.accentAmber.opacity(0.5)
        case .running: return DT.accent.opacity(0.5)
        case .done: return DT.accentGreen.opacity(0.3)
        case .failed: return DT.accentRed.opacity(0.5)
        case .skipped: return DT.border
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
