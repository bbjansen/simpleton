// Sources/Simpleton/Panels/KanbanBoardView.swift
import SimpletonCore
import SwiftUI
import UniformTypeIdentifiers

/// The Board-mode UI: a quick-tasks generator above four drag-and-drop kanban columns rendered from
/// `board.md`. Checking a card's box toggles `done`; dragging a card onto another column rewrites
/// `board.md` through the model. Columns are always the four canonical ones, in order.
struct KanbanBoardView: View {
    @ObservedObject var model: SpecDrivenDevModel
    @ObservedObject private var themeSettings = ThemeSettings.shared

    @State private var taskGoal = ""
    @State private var dropTarget: KanbanColumnKind?

    var body: some View {
        VStack(spacing: 0) {
            quickTasks
            ThemedDivider()
            columns
        }
    }

    // MARK: - Quick tasks

    private var quickTasks: some View {
        HStack(spacing: 6) {
            TextField("Generate tasks for a goal…", text: $taskGoal)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(DT.textPrimary)
                .padding(6)
                .background(DT.elevated.opacity(0.5))
                .cornerRadius(DT.radiusButton)
                .overlay(
                    RoundedRectangle(cornerRadius: DT.radiusButton)
                        .stroke(DT.border, lineWidth: 0.5)
                )
                .onSubmit(generateTasks)

            Button(action: generateTasks) {
                HStack(spacing: 4) {
                    if model.isGenerating {
                        ProgressView().controlSize(.small).scaleEffect(0.6)
                    } else {
                        Image(systemName: "sparkles").font(.system(size: 10))
                    }
                    Text(model.isGenerating ? "…" : "Tasks")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(DT.accent.opacity(0.18))
                .foregroundColor(DT.textPrimary)
                .cornerRadius(DT.radiusButton)
            }
            .buttonStyle(.plain)
            .disabled(model.isGenerating || taskGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    // MARK: - Columns

    private var columns: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 8) {
                ForEach(KanbanColumnKind.allCases, id: \.self) { kind in
                    column(kind)
                }
            }
            .padding(8)
        }
    }

    private func column(_ kind: KanbanColumnKind) -> some View {
        let cards = model.board.cards(in: kind)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(kind.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DT.textTertiary)
                Text("\(cards.count)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(DT.textFaint)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(DT.elevated.opacity(0.6))
                    .cornerRadius(DT.radiusPill)
                Spacer()
            }

            ForEach(cards) { card in
                cardView(card)
            }

            if cards.isEmpty {
                Text("Drop here")
                    .font(.system(size: 9))
                    .foregroundColor(DT.textFaint)
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: DT.radiusCard)
                .fill(DT.elevated.opacity(dropTarget == kind ? 0.55 : 0.25))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DT.radiusCard)
                .stroke(dropTarget == kind ? DT.accent : DT.border, lineWidth: dropTarget == kind ? 1 : 0.5)
        )
        .onDrop(of: [UTType.plainText], isTargeted: targetBinding(kind)) { providers in
            handleDrop(providers, into: kind)
        }
    }

    private func cardView(_ card: KanbanCard) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Button {
                Task { await model.toggleCard(card) }
            } label: {
                Image(systemName: card.done ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundColor(card.done ? DT.accentGreen : DT.textTertiary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .font(.system(size: 11))
                    .foregroundColor(card.done ? DT.textFaint : DT.textPrimary)
                    .strikethrough(card.done, color: DT.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
                if let notes = card.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 9))
                        .foregroundColor(DT.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DT.radiusButton)
                .fill(DT.surface.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DT.radiusButton)
                .stroke(DT.border, lineWidth: 0.5)
        )
        .onDrag { NSItemProvider(object: card.id as NSString) }
    }

    // MARK: - Drag & drop

    private func targetBinding(_ kind: KanbanColumnKind) -> Binding<Bool> {
        Binding(
            get: { dropTarget == kind },
            set: { isTargeted in dropTarget = isTargeted ? kind : (dropTarget == kind ? nil : dropTarget) }
        )
    }

    private func handleDrop(_ providers: [NSItemProvider], into kind: KanbanColumnKind) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { item, _ in
            guard let cardID = item as? String else { return }
            Task { @MainActor in
                dropTarget = nil
                guard let card = cardFor(id: cardID) else { return }
                await model.moveCard(card, to: kind)
            }
        }
        return true
    }

    private func cardFor(id: String) -> KanbanCard? {
        for kind in KanbanColumnKind.allCases {
            if let card = model.board.cards(in: kind).first(where: { $0.id == id }) {
                return card
            }
        }
        return nil
    }

    // MARK: - Actions

    private func generateTasks() {
        let captured = taskGoal
        Task { await model.generateTasks(goal: captured) }
    }
}
