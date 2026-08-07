import SimpletonCore
// Sources/Simpleton/Views/PaneIndicatorBar.swift
import SwiftUI

struct PaneIndicatorBar: View {
    @ObservedObject var conversation: TabConversation
    @ObservedObject private var themeSettings = ThemeSettings.shared

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(conversation.paneOrder, id: \.self) { paneID in
                    let label = conversation.paneLabels[paneID] ?? "Pane"
                    let isFocused = conversation.buildCompositeContext()?.focusedPaneID == paneID
                    Button(action: { conversation.targetPaneID = paneID }) {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(isFocused ? DT.accentGreen : DT.textFaint.opacity(0.6))
                                .frame(width: 6, height: 6)
                            Text(label)
                                .font(.system(size: 9))
                                .foregroundColor(DT.textSecondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            conversation.targetPaneID == paneID
                                ? themeSettings.accent.opacity(0.2) : DT.hover
                        )
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 4)
        .background(DT.base)
    }
}
