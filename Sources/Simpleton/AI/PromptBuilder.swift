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

    static func buildWatchPrompt(trigger: String, paneOutput: String) -> String {
        return """
        You are a terminal monitoring agent. A watch trigger fired in the user's terminal.

        TRIGGER: \(trigger)

        RECENT TERMINAL OUTPUT:
        \(paneOutput)

        Analyze the situation:
        1. What happened? (brief diagnosis)
        2. Is this an error that needs fixing? If so, what's the likely cause?
        3. Suggested next steps (be specific and actionable)

        Be concise — this is a background notification, not a conversation. Focus on the most important information.
        """
    }
}
