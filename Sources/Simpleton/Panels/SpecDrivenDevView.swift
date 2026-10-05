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

            if model.activeMode == .board {
                KanbanBoardView(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch model.activeMode {
                case .brainstorm, .spec, .plan:
                    goalControls
                case .act:
                    actNotice
                case .board:
                    EmptyView()
                }

                pendingBar
                ThemedDivider()
                artifactSlot
            }

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

    // MARK: - Goal-driven modes (brainstorm / spec / plan)

    private var goalPrompt: String {
        switch model.activeMode {
        case .brainstorm: return "What do you want to explore?"
        case .spec: return "What should the spec cover?"
        default: return "What do you want to build?"
        }
    }

    private var generateLabel: String {
        switch model.activeMode {
        case .brainstorm: return "Brainstorm"
        case .spec: return "Generate Spec"
        default: return "Generate Plan"
        }
    }

    private var goalControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(goalPrompt)
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
                        Text(model.isGenerating ? "Generating…" : generateLabel)
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

    // MARK: - Pending approval

    @ViewBuilder private var pendingBar: some View {
        if model.pending != nil {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.bubble")
                    .font(.system(size: 10))
                    .foregroundColor(DT.accentAmber)
                Text("Proposed — review, then approve to write the file.")
                    .font(.system(size: 10))
                    .foregroundColor(DT.textTertiary)
                    .lineLimit(1)
                Spacer()
                Button("Discard") { Task { await model.discardPending() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(DT.textSecondary)
                Button("Approve") { Task { await model.approvePending() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DT.accentGreen)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(DT.accentAmber.opacity(0.08))
        }
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
                        Text("Nothing yet. Describe a goal above and generate.")
                            .font(.system(size: 11))
                            .foregroundColor(DT.textFaint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    } else {
                        Text(renderedMarkdown)
                            .font(.system(size: 12))
                            .foregroundColor(DT.textPrimary)
                            .textSelection(.enabled)
                            .tint(DT.accentBlue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .environment(\.openURL, OpenURLAction { url in handleLink(url) })
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

    /// Custom URL scheme used to carry a detected code reference through SwiftUI's link machinery back
    /// to `handleLink`, which turns it into an editor command in the active pane.
    private static let codeRefScheme = "simpleton-coderef"

    /// The artifact rendered as inline markdown, with detected `path:line` tokens turned into clickable
    /// links. Segments between references are parsed as markdown; each reference becomes a link run
    /// carrying its path/line/col in a custom-scheme URL.
    private var renderedMarkdown: AttributedString {
        let text = model.artifactText
        let refs = CodeRefLinkParser.matches(in: text)
        guard !refs.isEmpty else { return inlineMarkdown(String(text)) }

        var result = AttributedString()
        var cursor = text.startIndex
        for ref in refs {
            if cursor < ref.range.lowerBound {
                result.append(inlineMarkdown(String(text[cursor..<ref.range.lowerBound])))
            }
            var run = AttributedString(String(text[ref.range]))
            run.font = DT.monoFont(size: 11)
            if let url = codeRefURL(for: ref) {
                run.link = url
            }
            result.append(run)
            cursor = ref.range.upperBound
        }
        if cursor < text.endIndex {
            result.append(inlineMarkdown(String(text[cursor...])))
        }
        return result
    }

    private func inlineMarkdown(_ fragment: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: fragment, options: options)) ?? AttributedString(fragment)
    }

    /// Encode a code reference into a `simpleton-coderef://line/col?path=…` URL. Path and positions ride
    /// in query items so `handleLink` can reconstruct the reference.
    private func codeRefURL(for ref: CodeRef) -> URL? {
        var components = URLComponents()
        components.scheme = Self.codeRefScheme
        components.host = "open"
        var items = [
            URLQueryItem(name: "path", value: ref.path),
            URLQueryItem(name: "line", value: String(ref.line)),
        ]
        if let col = ref.column { items.append(URLQueryItem(name: "col", value: String(col))) }
        components.queryItems = items
        return components.url
    }

    /// Handle an `openURL` from the preview. Code-ref links open the referenced file via the model;
    /// anything else (e.g. real `http` links) falls back to the system handler.
    private func handleLink(_ url: URL) -> OpenURLAction.Result {
        guard url.scheme == Self.codeRefScheme,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let path = components.queryItems?.first(where: { $0.name == "path" })?.value,
            let lineStr = components.queryItems?.first(where: { $0.name == "line" })?.value,
            let line = Int(lineStr)
        else {
            return .systemAction
        }
        model.openCodeRef(path: path, line: line)
        return .handled
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
        let mode = model.activeMode
        Task { await model.generate(for: mode, goal: captured) }
    }
}
