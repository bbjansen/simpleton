// Sources/Simpleton/Panels/SpecDrivenDevView.swift
import SimpletonCore
import SwiftUI

/// The Spec-Driven Dev panel UI. A mode control (Plan / Act), a goal field that generates a Markdown
/// implementation plan via the AI, and an artifact slot that toggles between a rendered Markdown
/// preview and a raw editor. The footer shows the artifact path and project root.
struct SpecDrivenDevView: View {
    @ObservedObject var model: SpecDrivenDevModel
    // Repaint DT.* tints on a live theme switch.
    @ObservedObject private var themeSettings = ThemeSettings.shared

    @State private var goal = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            ThemedDivider()
            modePicker
            ThemedDivider()

            switch model.activeMode {
            case .plan:
                planControls
            case .act:
                actNotice
            }

            ThemedDivider()
            artifactSlot
            ThemedDivider()
            footer
        }
        .themedGlass(DT.surface)
        .task { await model.start() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "checklist")
                .font(.system(size: 11))
                .foregroundColor(DT.accent)
            Text("Spec Dev")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DT.textMuted)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var modePicker: some View {
        Picker("", selection: modeBinding) {
            ForEach(SpecMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var modeBinding: Binding<SpecMode> {
        Binding(
            get: { model.activeMode },
            set: { newMode in Task { await model.setMode(newMode) } }
        )
    }

    // MARK: - Plan mode

    private var planControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What do you want to build?")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(DT.textTertiary)
            TextField("e.g. add rate limiting to the API", text: $goal, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(DT.textPrimary)
                .lineLimit(2...4)
                .padding(6)
                .background(DT.elevated.opacity(0.5))
                .cornerRadius(DT.radiusButton)
                .overlay(
                    RoundedRectangle(cornerRadius: DT.radiusButton)
                        .stroke(DT.border, lineWidth: 0.5)
                )
                .onSubmit { generate() }

            HStack {
                Button(action: generate) {
                    HStack(spacing: 5) {
                        if model.isGenerating {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                        }
                        Text(model.isGenerating ? "Generating…" : "Generate Plan")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DT.accent.opacity(0.18))
                    .foregroundColor(DT.textPrimary)
                    .cornerRadius(DT.radiusButton)
                }
                .buttonStyle(.plain)
                .disabled(model.isGenerating || goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    private var actNotice: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal")
                .font(.system(size: 10))
                .foregroundColor(DT.textTertiary)
            Text("Execute the plan from the AI Chat panel. This mode shows the current plan for reference.")
                .font(.system(size: 10))
                .foregroundColor(DT.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    // MARK: - Artifact slot (preview / edit)

    private var artifactSlot: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(model.activeArtifact.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DT.textTertiary)
                Spacer()
                if let error = model.errorMessage {
                    Text(error)
                        .font(.system(size: 9))
                        .foregroundColor(DT.accentRed)
                        .lineLimit(1)
                        .help(error)
                }
                slotActions
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)

            if model.isEditing {
                TextEditor(text: $model.artifactText)
                    .font(DT.monoFont(size: 12))
                    .foregroundColor(DT.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 4)
            } else {
                ScrollView {
                    if model.artifactText.isEmpty {
                        Text("No plan yet. Describe a goal above and generate one.")
                            .font(.system(size: 11))
                            .foregroundColor(DT.textFaint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    } else {
                        Text(renderedMarkdown)
                            .font(.system(size: 12))
                            .foregroundColor(DT.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var slotActions: some View {
        HStack(spacing: 8) {
            if model.isEditing {
                Button("Save") { Task { await model.saveArtifact() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DT.accent)
            } else {
                Button("Edit") { model.isEditing = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(DT.textSecondary)
                    .disabled(model.artifactText.isEmpty)
            }
        }
    }

    private var renderedMarkdown: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: model.artifactText, options: options))
            ?? AttributedString(model.artifactText)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(model.artifactPath)
                .font(DT.monoFont(size: 9))
                .foregroundColor(DT.textFaint)
                .lineLimit(1)
                .truncationMode(.head)
            Text("root: \(model.projectRoot)")
                .font(.system(size: 9))
                .foregroundColor(DT.textFaint)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    // MARK: - Actions

    private func generate() {
        let captured = goal
        Task { await model.generatePlan(goal: captured) }
    }
}
