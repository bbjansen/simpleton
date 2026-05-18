// Sources/Simpleton/AI/SkillStore.swift
import Foundation
import SimpletonCore

@MainActor
final class SkillStore: ObservableObject {

    @Published private(set) var builtInSkills: [Skill] = []
    @Published private(set) var userSkills: [Skill] = []

    var allSkills: [Skill] { builtInSkills + userSkills }

    private let userSkillsURL: URL

    init(appSupportDir: URL) {
        self.userSkillsURL = appSupportDir.appendingPathComponent("skills.json")
    }

    func load() {
        loadBuiltIns()
        loadUserSkills()
    }

    private func loadBuiltIns() {
        guard let url = Bundle.module.url(forResource: "builtin-skills", withExtension: "json") else {
            return
        }
        builtInSkills = (try? AtomicFileWriter.readJSON([Skill].self, from: url)) ?? []
    }

    private func loadUserSkills() {
        guard FileManager.default.fileExists(atPath: userSkillsURL.path) else { return }
        userSkills = (try? AtomicFileWriter.readJSON([Skill].self, from: userSkillsURL)) ?? []
    }

    func saveUserSkills() throws {
        try AtomicFileWriter.writeJSON(userSkills, to: userSkillsURL)
    }

    func addUserSkill(_ skill: Skill) throws {
        userSkills.append(skill)
        try saveUserSkills()
    }

    func updateUserSkill(_ skill: Skill) throws {
        guard let idx = userSkills.firstIndex(where: { $0.id == skill.id }) else { return }
        userSkills[idx] = skill
        try saveUserSkills()
    }

    func deleteUserSkill(id: UUID) throws {
        userSkills.removeAll { $0.id == id }
        try saveUserSkills()
    }

    func skill(forSlug slug: String) -> Skill? {
        allSkills.first { $0.slug == slug }
    }
}
