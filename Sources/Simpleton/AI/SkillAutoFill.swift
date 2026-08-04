// Sources/Simpleton/AI/SkillAutoFill.swift
import Foundation
import SimpletonCore

struct AutoFillResult {
    var values: [String: String]
    var aiSuggestedKeys: Set<String>  // params filled by AI — show ✦ indicator
}

enum SkillAutoFill {

    /// Phase 1: instant rule-based fill. No API call.
    static func phase1(skill: Skill, pane: PaneController) -> [String: String] {
        var result: [String: String] = [:]
        let ctx = AIContextBuilder.build(
            terminalView: pane.terminalView, cwd: pane.currentDirectory,
            shell: nil, includeSelection: true
        )
        for param in skill.parameters {
            guard let hint = param.autoFillHint else { continue }
            switch hint {
            case .cwd:
                if let cwd = ctx.cwd, !cwd.isEmpty { result[param.name] = cwd }
            case .selection:
                if let sel = ctx.selection, !sel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result[param.name] = sel.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            case .sshHost:
                if let host = pane.sshHost { result[param.name] = host }
            case .sshUser:
                if let user = pane.sshUser { result[param.name] = user }
            }
        }
        return result
    }

    /// Phase 2: AI suggests values for remaining empty fields (~500ms). Cancellable.
    static func phase2(
        skill: Skill,
        currentValues: [String: String],
        pane: PaneController,
        aiService: AIService
    ) async throws -> [String: String] {
        let empty = skill.parameters.filter {
            let v = currentValues[$0.name] ?? ""
            return v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !empty.isEmpty else { return [:] }

        let ctx = AIContextBuilder.build(
            terminalView: pane.terminalView, cwd: pane.currentDirectory,
            shell: nil, includeSelection: true
        )
        let ctxStr = AIContextBuilder.formatForPrompt(ctx)
        let paramList = empty.map { "\($0.name) (\($0.label))" }.joined(separator: ", ")

        let prompt = """
            Terminal context:
            \(ctxStr)

            Skill: "\(skill.name)"
            Suggest values for these empty parameters: \(paramList)

            Return ONLY a JSON object like {"paramName": "value"}.
            Return null for any parameter you are not confident about.
            """

        let response = try await aiService.complete(
            system: "You are a terminal context analyzer. Return only valid compact JSON, nothing else.",
            user: prompt,
            options: AIOptions(maxTokens: 150, temperature: 0)
        )

        guard let data = response.data(using: .utf8),
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return [:]
        }
        var result: [String: String] = [:]
        for param in empty {
            if let value = json[param.name] as? String, !value.isEmpty {
                result[param.name] = value
            }
        }
        return result
    }
}
