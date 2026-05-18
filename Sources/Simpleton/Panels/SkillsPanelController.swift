// Sources/Simpleton/Panels/SkillsPanelController.swift
import SwiftUI
import SimpletonCore

@MainActor
final class SkillsPanelVM: ObservableObject {
    @Published var query = ""
    @Published var selectedSkill: Skill?
    @Published var paramValues: [String: String] = [:]
    @Published var outputLines: [String] = []
    @Published var isRunning = false
    @Published var errorMessage: String?

    private var activeSession: AgentSession?
    let skillStore: SkillStore?
    let aiService: AIService?
    let currentPaneProvider: () -> PaneController?

    init(skillStore: SkillStore?, aiService: AIService?, currentPaneProvider: @escaping () -> PaneController?) {
        self.skillStore = skillStore
        self.aiService = aiService
        self.currentPaneProvider = currentPaneProvider
    }

    var filteredBuiltIn: [Skill] { filter(skillStore?.builtInSkills ?? []) }
    var filteredUser: [Skill] { filter(skillStore?.userSkills ?? []) }

    private func filter(_ skills: [Skill]) -> [Skill] {
        if query.isEmpty { return skills }
        let q = query.lowercased()
        return skills.filter { $0.name.lowercased().contains(q) || $0.slug.lowercased().contains(q) }
    }

    func select(_ skill: Skill) {
        selectedSkill = skill
        paramValues = [:]
        outputLines = []
        errorMessage = nil
    }

    func run(pane: PaneController) async {
        guard let skill = selectedSkill, let aiService = aiService else { return }
        outputLines = []
        errorMessage = nil
        isRunning = true

        let session = AgentSession(aiService: aiService)
        activeSession = session

        session.onMessage = { [weak self] msg in
            self?.outputLines.append(msg.content)
        }
        session.onError = { [weak self] err in
            self?.errorMessage = err
            self?.isRunning = false
        }
        session.onComplete = { [weak self] in
            self?.isRunning = false
        }
        session.onApprovalNeeded = { _, _, handler in
            handler(.allow)
        }

        await session.run(skill: skill, params: paramValues, pane: pane, autopilot: true)
        isRunning = false
        activeSession = nil
    }

    func cancel() {
        activeSession?.cancel()
        isRunning = false
    }
}

struct SkillsPanelView: View {
    let skillStore: SkillStore?
    let aiService: AIService?
    let currentPaneProvider: () -> PaneController?

    @StateObject private var vm: SkillsPanelVM

    init(skillStore: SkillStore?, aiService: AIService?, currentPaneProvider: @escaping () -> PaneController?) {
        self.skillStore = skillStore
        self.aiService = aiService
        self.currentPaneProvider = currentPaneProvider
        _vm = StateObject(wrappedValue: SkillsPanelVM(
            skillStore: skillStore,
            aiService: aiService,
            currentPaneProvider: currentPaneProvider
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(.system(size: 11))
                TextField("Search skills…", text: $vm.query).font(.system(size: 11))
            }
            .padding(8)

            Divider()

            // Skill list
            ScrollView {
                VStack(spacing: 2) {
                    if !vm.filteredBuiltIn.isEmpty {
                        sectionHeader("Built-in")
                        ForEach(vm.filteredBuiltIn) { skill in skillRow(skill) }
                    }
                    if !vm.filteredUser.isEmpty {
                        sectionHeader("Your Skills")
                        ForEach(vm.filteredUser) { skill in skillRow(skill) }
                    }
                    if vm.filteredBuiltIn.isEmpty && vm.filteredUser.isEmpty {
                        Text("No skills found")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                            .padding()
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 300)

            // Param form + run button
            if let skill = vm.selectedSkill {
                Divider()
                skillRunForm(skill: skill)
            }

            // Output
            if !vm.outputLines.isEmpty || vm.isRunning || vm.errorMessage != nil {
                Divider()
                outputView
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .simpletonActivateSkillPicker)) { _ in
            // Best-effort: clear the query to show all skills when picker is activated
            vm.query = ""
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6).padding(.top, 6).padding(.bottom, 2)
    }

    private func skillRow(_ skill: Skill) -> some View {
        Button(action: { vm.select(skill) }) {
            HStack(spacing: 8) {
                Image(systemName: skill.icon)
                    .font(.system(size: 12))
                    .foregroundColor(.purple)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(skill.name).font(.system(size: 11)).lineLimit(1)
                    Text("/\(skill.slug)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(vm.selectedSkill?.id == skill.id ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func skillRunForm(skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(skill.name).font(.system(size: 11, weight: .semibold))
            if !skill.description.isEmpty {
                Text(skill.description).font(.system(size: 10)).foregroundColor(.secondary)
            }
            ForEach(skill.parameters) { param in
                VStack(alignment: .leading, spacing: 2) {
                    Text(param.label).font(.system(size: 10)).foregroundColor(.secondary)
                    TextField(param.placeholder ?? param.name, text: Binding(
                        get: { vm.paramValues[param.name] ?? "" },
                        set: { vm.paramValues[param.name] = $0 }
                    ))
                    .font(.system(size: 11))
                }
            }
            HStack {
                Spacer()
                if vm.isRunning {
                    Button("Cancel") { vm.cancel() }.font(.system(size: 11))
                } else {
                    Button("Run") {
                        guard let pane = currentPaneProvider() else { return }
                        Task { await vm.run(pane: pane) }
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.borderedProminent)
                    .disabled(aiService == nil)
                }
            }
        }
        .padding(10)
    }

    private var outputView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(vm.outputLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let err = vm.errorMessage {
                    Text(err).font(.system(size: 10)).foregroundColor(.red)
                }
                if vm.isRunning {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.5)
                        Text("Running…").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }
            }
            .padding(8)
        }
        .frame(maxHeight: 180)
        .background(Color(nsColor: NSColor(white: 0.06, alpha: 1)))
    }
}
