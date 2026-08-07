import SimpletonCore
// Sources/Simpleton/Views/ChatViews/ChatInputView.swift
import SwiftUI

struct ChatInputView: View {
    @Binding var input: String
    @Binding var showSkillPicker: Bool
    let isStreaming: Bool
    let skillStore: SkillStore?
    let onSend: () -> Void
    let onCancel: () -> Void
    let onSkillSelected: (Skill) -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Bolt button for skill picker
            Button(action: { showSkillPicker.toggle() }) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12))
                    .foregroundColor(DT.accentAmber)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showSkillPicker, arrowEdge: .top) {
                if let store = skillStore {
                    SkillPickerSheet(
                        skillStore: store,
                        onSelect: { skill in
                            onSkillSelected(skill)
                        }, onDismiss: { showSkillPicker = false })
                }
            }

            TextField("Ask about your terminal session...", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit { onSend() }
                .disabled(isStreaming)

            if isStreaming {
                Button(action: onCancel) {
                    Image(systemName: "stop.circle.fill")
                        .foregroundColor(DT.accentRed)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundColor(input.isEmpty ? DT.textSecondary : DT.accent)
                }
                .buttonStyle(.plain)
                .disabled(input.isEmpty)
            }
        }
        .padding(12)
        .background(DT.surface)
    }
}
