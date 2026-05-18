// Sources/Simpleton/AI/Tools/SkillTools.swift
import Foundation
import SimpletonCore

@MainActor
struct SkillTools: ToolHandler {
    static let handledTools: Set<String> = ["list_skills", "run_skill"]

    func handle(name: String, args: [String: Any], context: ToolContext) async -> String {
        guard let store = context.skillStore else {
            return "Skills system not available"
        }

        switch name {
        case "list_skills":
            return handleListSkills(args, store: store)
        case "run_skill":
            return await handleRunSkill(args, store: store, context: context)
        default:
            return "Unknown skill tool: \(name)"
        }
    }

    // MARK: - list_skills

    private func handleListSkills(_ args: [String: Any], store: SkillStore) -> String {
        let category = args["category"] as? String
        let skills = store.allSkills

        let filtered: [Skill]
        if let category = category {
            filtered = skills.filter { $0.name.localizedCaseInsensitiveContains(category) ||
                $0.description.localizedCaseInsensitiveContains(category) ||
                $0.slug.localizedCaseInsensitiveContains(category) }
        } else {
            filtered = skills
        }

        if filtered.isEmpty {
            return category != nil
                ? "No skills matching '\(category!)'"
                : "No skills available"
        }

        var output = "Available skills (\(filtered.count)):\n\n"
        for skill in filtered {
            let params = skill.parameters.map { p in
                let req = p.required ? " (required)" : ""
                return "\(p.name): \(p.label)\(req)"
            }
            let paramStr = params.isEmpty ? "no parameters" : params.joined(separator: ", ")
            output += "  /\(skill.slug) — \(skill.name)\n"
            output += "    \(skill.description)\n"
            output += "    Params: \(paramStr)\n\n"
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - run_skill

    private func handleRunSkill(_ args: [String: Any], store: SkillStore, context: ToolContext) async -> String {
        guard let slug = args["slug"] as? String else {
            return "Missing 'slug' parameter. Use list_skills to see available skills."
        }
        guard let skill = store.skill(forSlug: slug) else {
            return "Skill '/\(slug)' not found. Use list_skills to see available skills."
        }

        // Extract parameters from args
        var params: [String: String] = [:]
        if let paramsDict = args["params"] as? [String: Any] {
            for (key, value) in paramsDict {
                params[key] = "\(value)"
            }
        }

        // Auto-fill missing params from context (phase 1 only — instant, no API call)
        if let pane = context.focusedPane as PaneController? {
            let autoFilled = SkillAutoFill.phase1(skill: skill, pane: pane)
            for (key, value) in autoFilled where params[key] == nil {
                params[key] = value
            }
        }

        // Check required params
        let missing = skill.parameters.filter { $0.required && (params[$0.name] ?? "").isEmpty }
        if !missing.isEmpty {
            let missingNames = missing.map { "\($0.name) (\($0.label))" }.joined(separator: ", ")
            return "Missing required parameters for /\(slug): \(missingNames). Provide them in the 'params' object."
        }

        // Substitute params into system prompt and return as task instructions
        var taskPrompt = skill.systemPrompt
        for (key, value) in params {
            taskPrompt = taskPrompt.replacingOccurrences(of: "{\(key)}", with: value)
        }

        let paramSummary = params.isEmpty ? "" : "\nParameters: \(params.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))"

        return """
        [Skill: \(skill.name) (/\(skill.slug))]\(paramSummary)

        Execute the following task:
        \(taskPrompt)

        Use run_command and other tools to complete this task step by step.
        """
    }
}
