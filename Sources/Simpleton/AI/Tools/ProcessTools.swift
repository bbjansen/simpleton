// Sources/Simpleton/AI/Tools/ProcessTools.swift
import Foundation

struct ProcessTools: ToolHandler {
    static let handledTools: Set<String> = [
        "find_process", "kill_process",
    ]

    func handle(name: String, args: [String: Any], context: ToolContext) async -> String {
        switch name {
        case "find_process":
            return await handleFindProcess(args, processRunner: context.processRunner)
        case "kill_process":
            return handleKillProcess(args)
        default:
            return "Unknown process tool: \(name)"
        }
    }

    private func handleFindProcess(_ args: [String: Any], processRunner: ProcessRunner) async -> String {
        guard let name = args["name"] as? String else {
            return "Missing 'name' parameter"
        }
        let result = await processRunner.run("/usr/bin/pgrep", args: ["-fl", name])
        return result.isEmpty ? "No processes matching '\(name)'" : result
    }

    private func handleKillProcess(_ args: [String: Any]) -> String {
        guard let pid = args["pid"] as? Int else {
            return "Missing 'pid' parameter"
        }
        let signal = args["signal"] as? String ?? "TERM"
        let sigNum: Int32
        switch signal.uppercased() {
        case "KILL", "9": sigNum = SIGKILL
        case "INT", "2": sigNum = SIGINT
        case "HUP", "1": sigNum = SIGHUP
        case "STOP", "19": sigNum = SIGSTOP
        case "CONT", "18": sigNum = SIGCONT
        case "USR1", "10": sigNum = SIGUSR1
        case "USR2", "12": sigNum = SIGUSR2
        case "QUIT", "3": sigNum = SIGQUIT
        case "TERM", "15": sigNum = SIGTERM
        default: sigNum = SIGTERM
        }
        let rc = kill(Int32(pid), sigNum)
        return rc == 0
            ? "Sent SIG\(signal.uppercased()) to PID \(pid)"
            : "Failed to signal PID \(pid): errno \(errno)"
    }
}
