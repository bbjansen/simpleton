// Sources/Simpleton/AI/Tools/SystemTools.swift
import Foundation
import AppKit

@MainActor
struct SystemTools: ToolHandler {
    static let handledTools: Set<String> = [
        "get_system_info", "get_env", "clipboard_copy",
    ]

    func handle(name: String, args: [String: Any], context: ToolContext) async -> String {
        switch name {
        case "get_system_info":
            return handleGetSystemInfo(processRunner: context.processRunner)
        case "get_env":
            return handleGetEnv(args)
        case "clipboard_copy":
            return handleClipboardCopy(args)
        default:
            return "Unknown system tool: \(name)"
        }
    }

    private func handleGetSystemInfo(processRunner: ProcessRunner) -> String {
        let info = ProcessInfo.processInfo
        return """
        OS: macOS \(info.operatingSystemVersionString)
        Host: \(Host.current().localizedName ?? "unknown")
        CPU cores: \(info.processorCount)
        Memory: \(info.physicalMemory / (1024 * 1024 * 1024)) GB
        Uptime: \(processRunner.formatUptime(info.systemUptime))
        User: \(NSUserName())
        Home: \(NSHomeDirectory())
        Shell: \(ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
        """
    }

    private func handleGetEnv(_ args: [String: Any]) -> String {
        let varName = args["name"] as? String
        if let name = varName {
            let value = ProcessInfo.processInfo.environment[name]
            return value ?? "[Not set]"
        } else {
            return ProcessInfo.processInfo.environment
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "\n")
        }
    }

    private func handleClipboardCopy(_ args: [String: Any]) -> String {
        guard let text = args["text"] as? String else {
            return "Missing 'text' parameter"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return "Copied \(text.count) chars to clipboard"
    }
}
