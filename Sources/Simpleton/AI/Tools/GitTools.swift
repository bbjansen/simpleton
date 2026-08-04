// Sources/Simpleton/AI/Tools/GitTools.swift
import Foundation

struct GitTools: ToolHandler {
    static let handledTools: Set<String> = [
        "get_git_status", "get_git_diff", "get_git_log",
    ]

    func handle(name: String, args: [String: Any], context: ToolContext) async -> String {
        let processRunner = context.processRunner

        switch name {
        case "get_git_status":
            let dir = args["directory"] as? String
            let result = await processRunner.run("/usr/bin/git", args: ["status", "--short"], cwd: dir)
            return result.isEmpty ? "[Clean working tree]" : result

        case "get_git_diff":
            let dir = args["directory"] as? String
            let staged = args["staged"] as? Bool ?? false
            var gitArgs = ["diff"]
            if staged { gitArgs.append("--cached") }
            gitArgs.append("--stat")
            let result = await processRunner.run("/usr/bin/git", args: gitArgs, cwd: dir)
            return result.isEmpty ? "[No changes]" : result

        case "get_git_log":
            let dir = args["directory"] as? String
            let count = args["count"] as? Int ?? 10
            let result = await processRunner.run(
                "/usr/bin/git", args: ["log", "--oneline", "-\(min(count, 50))"], cwd: dir)
            return result.isEmpty ? "[No commits]" : result

        default:
            return "Unknown git tool: \(name)"
        }
    }
}
