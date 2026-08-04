// Sources/Simpleton/Views/SkillsPreferencesTab.swift
import SwiftUI
import SimpletonCore
import UniformTypeIdentifiers

struct SkillsPreferencesTab: View {
    @ObservedObject var skillStore: SkillStore
    @State private var selectedSkillID: UUID?
    @State private var editingSkill: Skill?

    private var selectedSkill: Skill? {
        guard let id = selectedSkillID else { return nil }
        return skillStore.allSkills.first { $0.id == id }
    }

    var body: some View {
        HSplitView {
            // Left: skill list
            VStack(spacing: 0) {
                skillList
                Divider()
                HStack(spacing: 8) {
                    Button(action: newSkill) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("New")
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button(action: exportSkills) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
                .padding(8)
            }
            .frame(minWidth: 200, idealWidth: 260, maxWidth: 420)

            // Right: editor — .id forces re-creation when selected skill changes
            Group {
                if let skill = editingSkill {
                    SkillEditor(skill: skill, onSave: { updated in
                        try? skillStore.updateUserSkill(updated)
                        editingSkill = updated
                    }, onDelete: {
                        try? skillStore.deleteUserSkill(id: skill.id)
                        selectedSkillID = nil
                        editingSkill = nil
                    })
                    .id(skill.id)
                } else if let skill = selectedSkill, skill.builtIn {
                    SkillEditor(skill: skill, readOnly: true, onDuplicate: {
                        var copy = skill
                        copy.id = UUID()
                        copy.name = "\(skill.name) (Copy)"
                        copy.slug = "\(skill.slug)-copy"
                        copy.builtIn = false
                        try? skillStore.addUserSkill(copy)
                        selectedSkillID = copy.id
                        editingSkill = copy
                    })
                    .id(skill.id)
                } else {
                    Text("Select a skill to edit")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var skillList: some View {
        ScrollView {
            VStack(spacing: 2) {
                if !skillStore.builtInSkills.isEmpty {
                    sectionHeader("Built-in")
                    ForEach(skillStore.builtInSkills) { skill in skillRow(skill) }
                }
                if !skillStore.userSkills.isEmpty {
                    sectionHeader("Your Skills")
                    ForEach(skillStore.userSkills) { skill in skillRow(skill) }
                }
            }
            .padding(6)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func skillRow(_ skill: Skill) -> some View {
        Button(action: {
            selectedSkillID = skill.id
            editingSkill = skill.builtIn ? nil : skill
        }) {
            HStack(spacing: 8) {
                Image(systemName: skill.icon)
                    .font(.system(size: 12))
                    .foregroundColor(.purple)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(skill.name).font(.system(size: 11)).lineLimit(1)
                    Text("\(skill.parameters.count) params")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if skill.builtIn {
                    Text("built-in")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: NSColor(white: 0.2, alpha: 1)))
                        .cornerRadius(3)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(selectedSkillID == skill.id ? Color.accentColor.opacity(0.3) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private func newSkill() {
        let skill = Skill(
            name: "New Skill", slug: "new-skill", description: "",
            icon: "bolt", parameters: [], systemPrompt: "")
        try? skillStore.addUserSkill(skill)
        selectedSkillID = skill.id
        editingSkill = skill
    }

    private func exportSkills() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "my-skills.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? AtomicFileWriter.writeJSON(skillStore.userSkills, to: url)
        }
    }
}

// MARK: - Skill Editor

struct SkillEditor: View {
    @State var skill: Skill
    var readOnly: Bool = false
    var onSave: ((Skill) -> Void)?
    var onDelete: (() -> Void)?
    var onDuplicate: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if readOnly {
                    HStack {
                        Text("Built-in — read only")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Duplicate to Edit", action: { onDuplicate?() })
                            .font(.system(size: 11))
                    }
                    .padding(10)
                    .background(Color(nsColor: NSColor(white: 0.1, alpha: 1)))
                    .cornerRadius(8)
                }

                fieldGroup("Name") {
                    TextField("Skill name", text: $skill.name)
                        .disabled(readOnly)
                        .onChange(of: skill.name) { if !readOnly { onSave?(skill) } }
                }

                fieldGroup("Slug") {
                    HStack {
                        Text("/").foregroundColor(.secondary)
                        TextField("slug-name", text: $skill.slug)
                            .font(.system(size: 11, design: .monospaced))
                            .disabled(readOnly)
                            .onChange(of: skill.slug) { if !readOnly { onSave?(skill) } }
                    }
                }

                fieldGroup("Description") {
                    TextField("Short description", text: $skill.description)
                        .disabled(readOnly)
                        .onChange(of: skill.description) { if !readOnly { onSave?(skill) } }
                }

                fieldGroup("System Prompt") {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $skill.systemPrompt)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(minHeight: 100)
                            .disabled(readOnly)
                            .onChange(of: skill.systemPrompt) { if !readOnly { onSave?(skill) } }
                    }
                    Text("Use {paramName} as placeholders (highlighted in purple in-app)")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }

                fieldGroup("Parameters") {
                    ForEach(skill.parameters) { param in
                        paramRow(param)
                    }
                    if !readOnly {
                        Button(action: addParam) {
                            HStack {
                                Image(systemName: "plus.circle")
                                Text("Add parameter")
                            }
                            .font(.system(size: 11))
                            .foregroundColor(.purple)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !readOnly && onDelete != nil {
                    Button(action: { onDelete?() }) {
                        Text("Delete Skill")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    private func fieldGroup<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
            content()
        }
    }

    private func paramRow(_ param: SkillParameter) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .font(.system(size: 11))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(param.name)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.purple)
                    Text(param.type.rawValue)
                        .font(.system(size: 9))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color(nsColor: NSColor(white: 0.18, alpha: 1)))
                        .cornerRadius(3)
                    if param.required {
                        Text("required").font(.system(size: 9)).foregroundColor(.red)
                    }
                    if let hint = param.autoFillHint {
                        Text("auto:\(hint.rawValue)")
                            .font(.system(size: 9)).foregroundColor(Color.yellow.opacity(0.8))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.yellow.opacity(0.1)).cornerRadius(3)
                    }
                }
                Text(param.label).font(.system(size: 10)).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(8)
        .background(Color(nsColor: NSColor(white: 0.1, alpha: 1)))
        .cornerRadius(6)
    }

    private func addParam() {
        let p = SkillParameter(
            name: "param\(skill.parameters.count + 1)",
            label: "Parameter \(skill.parameters.count + 1)",
            type: .text
        )
        skill.parameters.append(p)
        onSave?(skill)
    }
}
