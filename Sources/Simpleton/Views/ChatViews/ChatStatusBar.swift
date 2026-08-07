// Sources/Simpleton/Views/ChatViews/ChatStatusBar.swift
import SwiftUI

struct ChatStatusBar: View {
    let stepNumber: Int
    @Binding var unlimitedTurns: Bool

    var body: some View {
        HStack(spacing: 6) {
            if stepNumber > 0 {
                Text("Step \(stepNumber)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(DT.textSecondary)
            }
            Spacer()
            Button(action: { unlimitedTurns.toggle() }) {
                HStack(spacing: 3) {
                    Image(systemName: unlimitedTurns ? "infinity" : "gauge.with.dots.needle.33percent")
                        .font(.system(size: 9))
                    Text(unlimitedTurns ? "Unlimited" : "25 turns")
                        .font(.system(size: 9))
                }
                .foregroundColor(unlimitedTurns ? DT.accentAmber : DT.textSecondary)
            }
            .buttonStyle(.plain)
            .help(
                unlimitedTurns
                    ? "Turn limit disabled — agent can run indefinitely" : "Agent limited to 25 tool calls per message")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(DT.base)
    }
}
