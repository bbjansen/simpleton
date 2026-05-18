// Sources/Simpleton/AI/PromptBuilder.swift
import Foundation
import SimpletonCore

@MainActor
struct PromptBuilder {
    func buildSystemPrompt(skill: Skill, params: [String: String], conversation: TabConversation, focusedPane: PaneController) -> String {
        let prompt = substituteParams(skill.systemPrompt, params: params)
        let ctxStr: String
        if let composite = conversation.buildCompositeContext() {
            ctxStr = AIContextBuilder.formatCompositeForPrompt(composite)
        } else {
            let ctx = AIContextBuilder.build(terminalView: focusedPane.terminalView, cwd: focusedPane.currentDirectory, shell: nil, includeSelection: false)
            ctxStr = AIContextBuilder.formatForPrompt(ctx)
        }
        return """
        You are an autonomous terminal agent. Complete the following task step by step using run_command.
        When the task is fully done, respond with a plain text summary (no tool call).

        TASK: \(prompt)

        CONTEXT:
        \(ctxStr)
        """
    }

    func buildSystemPromptLegacy(skill: Skill, params: [String: String], pane: PaneController) -> String {
        let prompt = substituteParams(skill.systemPrompt, params: params)
        let ctx = AIContextBuilder.build(terminalView: pane.terminalView, cwd: pane.currentDirectory, shell: nil, includeSelection: false)
        let ctxStr = AIContextBuilder.formatForPrompt(ctx)
        return """
        You are an autonomous terminal agent. Complete the following task step by step using run_command.
        When the task is fully done, respond with a plain text summary (no tool call).

        TASK: \(prompt)

        CONTEXT:
        \(ctxStr)
        """
    }

    func buildParamSummary(params: [String: String]) -> String {
        guard !params.isEmpty else { return "" }
        let list = params.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        return " Parameters: \(list)."
    }

    private func substituteParams(_ template: String, params: [String: String]) -> String {
        var result = template
        for (key, value) in params {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }
}
