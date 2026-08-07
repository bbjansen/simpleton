import SimpletonCore
// Sources/Simpleton/Views/SkillParameterForm.swift
import SwiftUI

struct SkillParameterForm: View {
    let skill: Skill
    @Binding var values: [String: String]
    let aiSuggestedKeys: Set<String>
    let panes: [(id: PaneID, label: String)]
    @Binding var selectedPaneID: PaneID?
    let onRun: () -> Void
    let onCancel: () -> Void
    var onFilePickerRequested: ((String) -> Void)?
    // Repaint this form's `DT.*` surfaces if a live theme switch happens while it's open.
    @ObservedObject private var themeSettings = ThemeSettings.shared

    private var canRun: Bool {
        skill.parameters.filter(\.required).allSatisfy {
            !(values[$0.name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: skill.icon)
                    .font(.system(size: 14))
                    .foregroundColor(DT.accent)
                Text(skill.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DT.textPrimary)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(DT.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(10)

            ThemedDivider()

            // Parameters
            if !skill.parameters.isEmpty {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(skill.parameters) { param in
                            paramField(param)
                        }
                    }
                    .padding(10)
                }
                .frame(maxHeight: 280)
                ThemedDivider()
            }

            // Pane picker + Run
            VStack(spacing: 8) {
                if panes.count > 1 {
                    Picker("Run in", selection: $selectedPaneID) {
                        ForEach(panes, id: \.id) { pane in
                            Text(pane.label).tag(Optional(pane.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.system(size: 11))
                }

                HStack {
                    Button(action: onCancel) {
                        Text("Cancel").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(DT.textSecondary)
                    Spacer()
                    Button(action: onRun) {
                        HStack(spacing: 4) {
                            Text("Run Skill")
                            Image(systemName: "play.fill")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(canRun ? DT.accent : DT.textFaint.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canRun)
                }
            }
            .padding(10)
        }
        .background(DT.surface)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DT.accent.opacity(0.4), lineWidth: 1))
    }

    @ViewBuilder
    private func paramField(_ param: SkillParameter) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(param.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DT.textMuted)
                if param.required {
                    Text("*").font(.system(size: 10)).foregroundColor(DT.accentRed)
                }
                if aiSuggestedKeys.contains(param.name) {
                    Text("✦").font(.system(size: 9)).foregroundColor(DT.accent)
                }
            }
            switch param.type {
            case .text, .filePath:
                HStack {
                    TextField(param.placeholder ?? "", text: binding(for: param.name))
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: param.type == .filePath ? .monospaced : .default))
                        .foregroundColor(DT.textPrimary)
                        .padding(6)
                        .background(DT.base)
                        .cornerRadius(5)
                    if param.type == .filePath {
                        Button(action: { onFilePickerRequested?(param.name) }) {
                            Image(systemName: "folder").font(.system(size: 11)).foregroundColor(DT.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            case .number:
                TextField(param.placeholder ?? "0", text: binding(for: param.name))
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(DT.textPrimary)
                    .padding(6)
                    .background(DT.base)
                    .cornerRadius(5)
            case .picker:
                Picker("", selection: binding(for: param.name)) {
                    ForEach(param.pickerOptions ?? [], id: \.self) { opt in
                        Text(opt).tag(opt)
                    }
                }
                .pickerStyle(.menu)
                .font(.system(size: 11))
                .onAppear {
                    if (values[param.name] ?? "").isEmpty,
                        let first = param.pickerOptions?.first
                    {
                        values[param.name] = first
                    }
                }
            }
        }
    }

    private func binding(for name: String) -> Binding<String> {
        Binding(
            get: { values[name] ?? "" },
            set: { values[name] = $0 }
        )
    }
}
