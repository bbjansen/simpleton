import SimpletonCore
// Sources/Simpleton/Views/PaneIndicatorBar.swift
import SwiftUI

struct PaneIndicatorBar: View {
    @ObservedObject var conversation: TabConversation

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(conversation.paneOrder, id: \.self) { paneID in
                    let label = conversation.paneLabels[paneID] ?? "Pane"
                    let isFocused = conversation.buildCompositeContext()?.focusedPaneID == paneID
                    Button(action: { conversation.targetPaneID = paneID }) {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(isFocused ? Color.green : Color.secondary.opacity(0.4))
                                .frame(width: 6, height: 6)
                            Text(label)
                                .font(.system(size: 9))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            conversation.targetPaneID == paneID
                                ? Color.accentColor.opacity(0.2) : Color(nsColor: NSColor(white: 0.12, alpha: 1))
                        )
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 4)
        .background(Color(nsColor: NSColor(white: 0.06, alpha: 1)))
    }
}
