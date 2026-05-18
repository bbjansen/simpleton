// Sources/Simpleton/AI/AgentSession.swift
import Foundation
import AppKit
import SimpletonCore

@MainActor
final class AgentSession: ObservableObject {

    enum State: Equatable {
        case idle
        case streaming
        case waitingApproval(cmd: String, explanation: String, toolCallID: String, paneLabel: String)
        case executing(cmd: String)
        case capturingOutput
        case done
        case error(String)
    }

    enum ApprovalAction { case allow, skip, stop }

    @Published private(set) var state: State = .idle
    @Published private(set) var stepNumber: Int = 0

    var onMessage: ((ChatMessage) -> Void)?
    /// (cmd, explanation, paneLabel, handler(action, overridePaneID?))
    var onApprovalNeeded: ((String, String, String, @escaping (ApprovalAction, PaneID?) -> Void) -> Void)?
    /// (cmd, output, paneLabel)
    var onCommandExecuted: ((String, String, String) -> Void)?
    var onComplete: (() -> Void)?
    var onError: ((String) -> Void)?

    private let aiService: AIService
    private var isCancelled = false
    private var pendingApprovalContinuation: CheckedContinuation<(ApprovalAction, PaneID?), Never>?
    private var turnCount = 0
    private let maxTurns = 25
    private let warningTurn = 15

    init(aiService: AIService) {
        self.aiService = aiService
    }

    func cancel() {
        isCancelled = true
        pendingApprovalContinuation?.resume(returning: (.stop, nil))
        pendingApprovalContinuation = nil
        aiService.cancelAll()
        state = .idle
    }

    // MARK: - Chat with Tools (free-text conversation that can execute commands)

    func chat(
        message: String,
        history: [ConversationTurn],
        systemPrompt: String,
        conversation: TabConversation,
        focusedPane: PaneController,
        autopilot: Bool
    ) async {
        isCancelled = false
        turnCount = 0
        stepNumber = 0
        var turns = history
        turns.append(.user(message))

        while !isCancelled {
            turnCount += 1
            if turnCount > maxTurns {
                onMessage?(ChatMessage(role: "assistant", content: "Reached the maximum number of steps (\(maxTurns)). Stopping to avoid runaway execution. Here's what was accomplished so far."))
                state = .done
                onComplete?()
                return
            }

            // Inject soft warning near the limit
            var turnOptions = AIOptions(maxTokens: 4000, temperature: 0.3)
            var effectiveSystem = systemPrompt
            if turnCount == warningTurn {
                effectiveSystem += "\n\n[SYSTEM NOTE: You are approaching the step limit (\(maxTurns)). Start wrapping up — finish the current task and provide a summary.]"
            }

            state = .streaming
            do {
                let result = try await aiService.agentTurn(system: effectiveSystem, turns: turns, options: turnOptions)
                switch result {
                case .text(let text):
                    onMessage?(ChatMessage(role: "assistant", content: text))
                    state = .done
                    onComplete?()
                    return

                case .toolCall(let id, let name, let args):
                    if name == "run_command" { stepNumber += 1 }
                    let result = await handleToolCall(
                        id: id, name: name, args: args,
                        conversation: conversation, focusedPane: focusedPane,
                        autopilot: autopilot, turns: &turns
                    )
                    if result == .stopped { return }
                }
            } catch {
                state = .error(error.localizedDescription)
                onError?(error.localizedDescription)
                return
            }
        }
    }

    private enum ToolHandleResult { case continued, stopped }

    /// Dispatch a tool call to the appropriate handler.
    private func handleToolCall(
        id: String, name: String, args: [String: Any],
        conversation: TabConversation, focusedPane: PaneController,
        autopilot: Bool, turns: inout [ConversationTurn]
    ) async -> ToolHandleResult {
        switch name {
        case "run_command":
            return await handleRunCommand(
                id: id, args: args, conversation: conversation,
                focusedPane: focusedPane, autopilot: autopilot, turns: &turns
            )
        case "read_pane_output":
            let paneNum = args["pane"] as? Int
            let lines = min(args["lines"] as? Int ?? 50, 200)
            let resolved = conversation.resolvePane(number: paneNum)
            let pane = resolved?.pane ?? focusedPane
            let label = resolved?.label ?? "focused pane"

            let output = readTerminalOutput(pane: pane, lines: lines)
            turns.append(.toolResult(toolCallID: id, output: "[\(label)] Recent output (\(lines) lines):\n\(output)"))
            return .continued

        case "list_panes":
            let output = listPanesOutput(conversation: conversation, focusedPane: focusedPane)
            turns.append(.toolResult(toolCallID: id, output: output))
            return .continued

        case "get_pane_state":
            let paneNum = args["pane"] as? Int ?? 1
            let resolved = conversation.resolvePane(number: paneNum)
            if let pane = resolved?.pane {
                let output = paneStateOutput(pane: pane, label: resolved?.label ?? "Pane \(paneNum)")
                turns.append(.toolResult(toolCallID: id, output: output))
            } else {
                turns.append(.toolResult(toolCallID: id, output: "Pane \(paneNum) not found."))
            }
            return .continued

        case "read_file":
            guard let path = args["path"] as? String else {
                turns.append(.toolResult(toolCallID: id, output: "Missing 'path' parameter"))
                return .continued
            }
            let expandedPath = NSString(string: path).expandingTildeInPath
            do {
                let content = try String(contentsOfFile: expandedPath, encoding: .utf8)
                let maxChars = 10_000
                let truncated = content.count > maxChars
                let result = truncated ? String(content.prefix(maxChars)) + "\n\n[... truncated at \(maxChars) chars, file is \(content.count) chars total]" : content
                turns.append(.toolResult(toolCallID: id, output: result))
            } catch {
                turns.append(.toolResult(toolCallID: id, output: "Error reading \(path): \(error.localizedDescription)"))
            }
            return .continued

        case "write_file":
            guard let path = args["path"] as? String,
                  let content = args["content"] as? String else {
                turns.append(.toolResult(toolCallID: id, output: "Missing 'path' or 'content' parameter"))
                return .continued
            }
            let expandedPath = NSString(string: path).expandingTildeInPath
            do {
                let dir = (expandedPath as NSString).deletingLastPathComponent
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                try content.write(toFile: expandedPath, atomically: true, encoding: .utf8)
                turns.append(.toolResult(toolCallID: id, output: "Wrote \(content.count) chars to \(path)"))
            } catch {
                turns.append(.toolResult(toolCallID: id, output: "Error writing \(path): \(error.localizedDescription)"))
            }
            return .continued

        case "list_directory":
            let path = args["path"] as? String ?? "."
            let expandedPath = NSString(string: path).expandingTildeInPath
            do {
                let items = try FileManager.default.contentsOfDirectory(atPath: expandedPath)
                var lines: [String] = []
                for item in items.sorted() {
                    let fullPath = (expandedPath as NSString).appendingPathComponent(item)
                    var isDir: ObjCBool = false
                    FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir)
                    let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath)
                    let size = attrs?[.size] as? UInt64 ?? 0
                    let suffix = isDir.boolValue ? "/" : ""
                    lines.append("\(item)\(suffix)  \(isDir.boolValue ? "dir" : formatFileSize(size))")
                }
                turns.append(.toolResult(toolCallID: id, output: lines.isEmpty ? "[Empty directory]" : lines.joined(separator: "\n")))
            } catch {
                turns.append(.toolResult(toolCallID: id, output: "Error listing \(path): \(error.localizedDescription)"))
            }
            return .continued

        case "search_files":
            guard let pattern = args["pattern"] as? String else {
                turns.append(.toolResult(toolCallID: id, output: "Missing 'pattern' parameter"))
                return .continued
            }
            let dir = args["directory"] as? String ?? "."
            let expandedDir = NSString(string: dir).expandingTildeInPath
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
            process.arguments = ["-r", "-n", "-l", "--include=*", pattern, expandedDir]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let output = String(data: data, encoding: .utf8) ?? ""
                let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
                if lines.isEmpty {
                    turns.append(.toolResult(toolCallID: id, output: "No files matching '\(pattern)' in \(dir)"))
                } else {
                    let maxFiles = 50
                    let truncated = lines.count > maxFiles
                    let result = lines.prefix(maxFiles).joined(separator: "\n") + (truncated ? "\n\n[... and \(lines.count - maxFiles) more files]" : "")
                    turns.append(.toolResult(toolCallID: id, output: result))
                }
            } catch {
                turns.append(.toolResult(toolCallID: id, output: "Error searching: \(error.localizedDescription)"))
            }
            return .continued

        case "get_system_info":
            let info = ProcessInfo.processInfo
            let output = """
            OS: macOS \(info.operatingSystemVersionString)
            Host: \(Host.current().localizedName ?? "unknown")
            CPU cores: \(info.processorCount)
            Memory: \(info.physicalMemory / (1024 * 1024 * 1024)) GB
            Uptime: \(formatUptime(info.systemUptime))
            User: \(NSUserName())
            Home: \(NSHomeDirectory())
            Shell: \(ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
            """
            turns.append(.toolResult(toolCallID: id, output: output))
            return .continued

        case "edit_file":
            guard let path = args["path"] as? String,
                  let oldText = args["old_text"] as? String,
                  let newText = args["new_text"] as? String else {
                turns.append(.toolResult(toolCallID: id, output: "Missing 'path', 'old_text', or 'new_text' parameter"))
                return .continued
            }
            let expandedPath = NSString(string: path).expandingTildeInPath
            do {
                var content = try String(contentsOfFile: expandedPath, encoding: .utf8)
                let occurrences = content.components(separatedBy: oldText).count - 1
                if occurrences == 0 {
                    turns.append(.toolResult(toolCallID: id, output: "Error: old_text not found in \(path). Make sure it matches exactly (including whitespace)."))
                } else if occurrences > 1 && !(args["replace_all"] as? Bool ?? false) {
                    turns.append(.toolResult(toolCallID: id, output: "Error: old_text found \(occurrences) times in \(path). Set replace_all=true or provide more context to make the match unique."))
                } else {
                    if args["replace_all"] as? Bool ?? false {
                        content = content.replacingOccurrences(of: oldText, with: newText)
                    } else {
                        if let range = content.range(of: oldText) {
                            content.replaceSubrange(range, with: newText)
                        }
                    }
                    try content.write(toFile: expandedPath, atomically: true, encoding: .utf8)
                    turns.append(.toolResult(toolCallID: id, output: "Edited \(path): replaced \(oldText.count) chars with \(newText.count) chars"))
                }
            } catch {
                turns.append(.toolResult(toolCallID: id, output: "Error editing \(path): \(error.localizedDescription)"))
            }
            return .continued

        case "get_git_status":
            let dir = args["directory"] as? String
            let result = runSubprocess("/usr/bin/git", args: ["status", "--short"], cwd: dir)
            turns.append(.toolResult(toolCallID: id, output: result.isEmpty ? "[Clean working tree]" : result))
            return .continued

        case "get_git_diff":
            let dir = args["directory"] as? String
            let staged = args["staged"] as? Bool ?? false
            var gitArgs = ["diff"]
            if staged { gitArgs.append("--cached") }
            gitArgs.append("--stat")
            let result = runSubprocess("/usr/bin/git", args: gitArgs, cwd: dir)
            turns.append(.toolResult(toolCallID: id, output: result.isEmpty ? "[No changes]" : result))
            return .continued

        case "get_git_log":
            let dir = args["directory"] as? String
            let count = args["count"] as? Int ?? 10
            let result = runSubprocess("/usr/bin/git", args: ["log", "--oneline", "-\(min(count, 50))"], cwd: dir)
            turns.append(.toolResult(toolCallID: id, output: result.isEmpty ? "[No commits]" : result))
            return .continued

        case "clipboard_copy":
            guard let text = args["text"] as? String else {
                turns.append(.toolResult(toolCallID: id, output: "Missing 'text' parameter"))
                return .continued
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            turns.append(.toolResult(toolCallID: id, output: "Copied \(text.count) chars to clipboard"))
            return .continued

        case "send_keys":
            guard let keys = args["keys"] as? String else {
                turns.append(.toolResult(toolCallID: id, output: "Missing 'keys' parameter"))
                return .continued
            }
            let paneNum = args["pane"] as? Int
            let resolved = conversation.resolvePane(number: paneNum)
            let pane = resolved?.pane ?? focusedPane
            let label = resolved?.label ?? "focused pane"
            // Map special key names to control characters
            let mapped: String
            switch keys.lowercased() {
            case "ctrl+c", "ctrl-c": mapped = "\u{03}"
            case "ctrl+d", "ctrl-d": mapped = "\u{04}"
            case "ctrl+z", "ctrl-z": mapped = "\u{1A}"
            case "ctrl+l", "ctrl-l": mapped = "\u{0C}"
            case "enter", "return": mapped = "\n"
            case "tab": mapped = "\t"
            case "escape", "esc": mapped = "\u{1B}"
            case "up": mapped = "\u{1B}[A"
            case "down": mapped = "\u{1B}[B"
            case "left": mapped = "\u{1B}[D"
            case "right": mapped = "\u{1B}[C"
            default: mapped = keys
            }
            pane.terminalView.send(data: Array(mapped.utf8)[...])
            turns.append(.toolResult(toolCallID: id, output: "Sent '\(keys)' to \(label)"))
            return .continued

        case "get_env":
            let varName = args["name"] as? String
            if let name = varName {
                let value = ProcessInfo.processInfo.environment[name]
                turns.append(.toolResult(toolCallID: id, output: value ?? "[Not set]"))
            } else {
                // Return all env vars
                let env = ProcessInfo.processInfo.environment
                    .sorted(by: { $0.key < $1.key })
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: "\n")
                turns.append(.toolResult(toolCallID: id, output: env))
            }
            return .continued

        case "http_request":
            guard let urlStr = args["url"] as? String,
                  let url = URL(string: urlStr) else {
                turns.append(.toolResult(toolCallID: id, output: "Missing or invalid 'url' parameter"))
                return .continued
            }
            let method = (args["method"] as? String ?? "GET").uppercased()
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 15
            if let headers = args["headers"] as? [String: String] {
                for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
            }
            if let body = args["body"] as? String {
                request.httpBody = body.data(using: .utf8)
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
            }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let httpResponse = response as? HTTPURLResponse
                let status = httpResponse?.statusCode ?? 0
                let bodyStr = String(data: data, encoding: .utf8) ?? "[Binary data, \(data.count) bytes]"
                let maxChars = 5000
                let truncated = bodyStr.count > maxChars ? String(bodyStr.prefix(maxChars)) + "\n[... truncated]" : bodyStr
                turns.append(.toolResult(toolCallID: id, output: "HTTP \(status)\n\(truncated)"))
            } catch {
                turns.append(.toolResult(toolCallID: id, output: "HTTP error: \(error.localizedDescription)"))
            }
            return .continued

        case "check_port":
            guard let port = args["port"] as? Int else {
                turns.append(.toolResult(toolCallID: id, output: "Missing 'port' parameter"))
                return .continued
            }
            let host = args["host"] as? String ?? "localhost"
            let result = runSubprocess("/usr/sbin/lsof", args: ["-i", ":\(port)", "-P", "-n"])
            if result.isEmpty {
                turns.append(.toolResult(toolCallID: id, output: "Port \(port) on \(host): not in use"))
            } else {
                turns.append(.toolResult(toolCallID: id, output: "Port \(port) on \(host):\n\(result)"))
            }
            return .continued

        case "find_process":
            guard let name = args["name"] as? String else {
                turns.append(.toolResult(toolCallID: id, output: "Missing 'name' parameter"))
                return .continued
            }
            let result = runSubprocess("/usr/bin/pgrep", args: ["-fl", name])
            turns.append(.toolResult(toolCallID: id, output: result.isEmpty ? "No processes matching '\(name)'" : result))
            return .continued

        case "kill_process":
            guard let pid = args["pid"] as? Int else {
                turns.append(.toolResult(toolCallID: id, output: "Missing 'pid' parameter"))
                return .continued
            }
            let signal = args["signal"] as? String ?? "TERM"
            let sigNum: Int32
            switch signal.uppercased() {
            case "KILL", "9": sigNum = SIGKILL
            case "INT", "2": sigNum = SIGINT
            case "HUP", "1": sigNum = SIGHUP
            default: sigNum = SIGTERM
            }
            let rc = kill(Int32(pid), sigNum)
            turns.append(.toolResult(toolCallID: id, output: rc == 0 ? "Sent SIG\(signal.uppercased()) to PID \(pid)" : "Failed to signal PID \(pid): errno \(errno)"))
            return .continued

        default:
            turns.append(.toolResult(toolCallID: id, output: "Unknown tool: \(name)"))
            return .continued
        }
    }

    private func runSubprocess(_ executable: String, args: [String], cwd: String? = nil) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        if let cwd = cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: NSString(string: cwd).expandingTildeInPath)
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            let maxChars = 8000
            if output.count > maxChars {
                return String(output.prefix(maxChars)) + "\n[... truncated]"
            }
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    private func formatFileSize(_ bytes: UInt64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return "\(bytes / (1024 * 1024)) MB"
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let mins = (Int(seconds) % 3600) / 60
        if hours > 24 { return "\(hours / 24)d \(hours % 24)h" }
        return "\(hours)h \(mins)m"
    }

    /// Handle run_command tool call with approval flow.
    private func handleRunCommand(
        id: String, args: [String: Any],
        conversation: TabConversation, focusedPane: PaneController,
        autopilot: Bool, turns: inout [ConversationTurn]
    ) async -> ToolHandleResult {
        guard let cmd = args["cmd"] as? String else {
            turns.append(.toolResult(toolCallID: id, output: "Missing 'cmd' parameter"))
            return .continued
        }
        let explanation = args["explanation"] as? String ?? ""
        let paneNumber = args["pane"] as? Int
        let resolved = conversation.resolvePane(number: paneNumber)
        let targetPane = resolved?.pane ?? focusedPane
        let targetLabel = resolved?.label ?? "focused pane"

        if autopilot {
            await executeCommand(cmd, toolCallID: id, explanation: explanation, pane: targetPane, paneLabel: targetLabel, wasFallback: resolved?.wasFallback ?? false, turns: &turns)
            return .continued
        }

        state = .waitingApproval(cmd: cmd, explanation: explanation, toolCallID: id, paneLabel: targetLabel)
        let (action, overridePaneID) = await withCheckedContinuation { (continuation: CheckedContinuation<(ApprovalAction, PaneID?), Never>) in
            pendingApprovalContinuation = continuation
            onApprovalNeeded?(cmd, explanation, targetLabel) { [weak self] action, overrideID in
                self?.pendingApprovalContinuation?.resume(returning: (action, overrideID))
                self?.pendingApprovalContinuation = nil
            }
        }
        switch action {
        case .allow:
            let finalPane: PaneController
            let finalLabel: String
            if let overrideID = overridePaneID,
               let idx = conversation.paneOrder.firstIndex(of: overrideID),
               let overrideResolved = conversation.resolvePane(number: idx + 1) {
                finalPane = overrideResolved.pane
                finalLabel = overrideResolved.label
            } else {
                finalPane = targetPane
                finalLabel = targetLabel
            }
            await executeCommand(cmd, toolCallID: id, explanation: explanation, pane: finalPane, paneLabel: finalLabel, wasFallback: false, turns: &turns)
            return .continued
        case .skip:
            turns.append(.toolResult(toolCallID: id, output: "[Command skipped by user]"))
            return .continued
        case .stop:
            state = .done
            onComplete?()
            return .stopped
        }
    }

    // MARK: - Read-Only Tool Implementations

    private func readTerminalOutput(pane: PaneController, lines: Int) -> String {
        let terminal = pane.terminalView.getTerminal()
        let totalRows = terminal.rows
        let startRow = max(0, totalRows - lines)
        var outputLines: [String] = []
        for row in startRow..<totalRows {
            if let line = terminal.getLine(row: row) {
                let text = line.translateToString(trimRight: true)
                if !text.isEmpty { outputLines.append(text) }
            }
        }
        let output = outputLines.joined(separator: "\n")
        return output.isEmpty ? "[No output]" : output
    }

    private func listPanesOutput(conversation: TabConversation, focusedPane: PaneController) -> String {
        guard let context = conversation.buildCompositeContext() else {
            return "Panes: 1 (focused)\nCWD: \(focusedPane.currentDirectory ?? "unknown")"
        }
        var lines: [String] = ["Panes in this tab:\n"]
        for pane in context.panes {
            let focus = pane.isFocused ? " (focused)" : ""
            let cwdStr = pane.cwd ?? "unknown"
            let shellStr = pane.shell ?? "shell"
            let connStr: String
            switch pane.connectionType {
            case .local: connStr = "local"
            case .ssh: connStr = "SSH"
            }
            lines.append("  \(pane.label)\(focus) — \(cwdStr) [\(shellStr), \(connStr)]")
        }
        return lines.joined(separator: "\n")
    }

    private func paneStateOutput(pane: PaneController, label: String) -> String {
        let cwd = pane.currentDirectory ?? "unknown"
        let connStr: String
        let shellStr: String
        switch pane.connectionType {
        case .local(let shell, _):
            connStr = "local"
            shellStr = URL(fileURLWithPath: shell).lastPathComponent
        case .ssh:
            connStr = "SSH (\(pane.sshHost ?? "unknown"))"
            shellStr = "remote"
        }
        let stateStr: String
        switch pane.state {
        case .running: stateStr = "running"
        case .exited(let code): stateStr = "exited (code \(code))"
        case .disconnected: stateStr = "disconnected"
        case .connecting: stateStr = "connecting"
        case .authRequired: stateStr = "auth required"
        }
        let output = readTerminalOutput(pane: pane, lines: 30)
        return """
        \(label)
        CWD: \(cwd)
        Shell: \(shellStr)
        Connection: \(connStr)
        State: \(stateStr)
        Recent output:
        \(output)
        """
    }

    // MARK: - Skill Execution (Multi-Pane)

    func run(skill: Skill, params: [String: String], conversation: TabConversation, focusedPane: PaneController, autopilot: Bool) async {
        isCancelled = false
        let system = buildSystemPrompt(skill: skill, params: params, conversation: conversation, focusedPane: focusedPane)
        let initialMessage = "Run the \(skill.name) skill.\(buildParamSummary(params: params))"
        var turns: [ConversationTurn] = [.user(initialMessage)]

        while !isCancelled {
            state = .streaming
            do {
                let result = try await aiService.agentTurn(system: system, turns: turns)
                switch result {
                case .text(let text):
                    onMessage?(ChatMessage(role: "assistant", content: text))
                    state = .done
                    onComplete?()
                    return

                case .toolCall(let id, let name, let args):
                    let result = await handleToolCall(
                        id: id, name: name, args: args,
                        conversation: conversation, focusedPane: focusedPane,
                        autopilot: autopilot, turns: &turns
                    )
                    if result == .stopped { return }
                }
            } catch {
                state = .error(error.localizedDescription)
                onError?(error.localizedDescription)
                return
            }
        }
    }

    // MARK: - Legacy Single-Pane Entry Point

    func run(skill: Skill, params: [String: String], pane: PaneController, autopilot: Bool) async {
        isCancelled = false
        let system = buildSystemPromptLegacy(skill: skill, params: params, pane: pane)
        let initialMessage = "Run the \(skill.name) skill.\(buildParamSummary(params: params))"
        var turns: [ConversationTurn] = [.user(initialMessage)]

        while !isCancelled {
            state = .streaming
            do {
                let result = try await aiService.agentTurn(system: system, turns: turns)
                switch result {
                case .text(let text):
                    onMessage?(ChatMessage(role: "assistant", content: text))
                    state = .done
                    onComplete?()
                    return
                case .toolCall(let id, let name, let args):
                    // Legacy path: only handle run_command, ignore other tools
                    guard name == "run_command", let cmd = args["cmd"] as? String else {
                        turns.append(.toolResult(toolCallID: id, output: "Tool \(name) not available in legacy mode"))
                        continue
                    }
                    let explanation = args["explanation"] as? String ?? ""
                    if autopilot {
                        await executeCommand(cmd, toolCallID: id, explanation: explanation, pane: pane, paneLabel: "focused pane", wasFallback: false, turns: &turns)
                    } else {
                        state = .waitingApproval(cmd: cmd, explanation: explanation, toolCallID: id, paneLabel: "focused pane")
                        let (action, _) = await withCheckedContinuation { (continuation: CheckedContinuation<(ApprovalAction, PaneID?), Never>) in
                            pendingApprovalContinuation = continuation
                            onApprovalNeeded?(cmd, explanation, "focused pane") { [weak self] action, _ in
                                self?.pendingApprovalContinuation?.resume(returning: (action, nil))
                                self?.pendingApprovalContinuation = nil
                            }
                        }
                        switch action {
                        case .allow:
                            await executeCommand(cmd, toolCallID: id, explanation: explanation, pane: pane, paneLabel: "focused pane", wasFallback: false, turns: &turns)
                        case .skip:
                            turns.append(.toolResult(toolCallID: id, output: "[Command skipped by user]"))
                        case .stop:
                            state = .done
                            onComplete?()
                            return
                        }
                    }
                }
            } catch {
                state = .error(error.localizedDescription)
                onError?(error.localizedDescription)
                return
            }
        }
    }

    // MARK: - Command Execution

    private func executeCommand(
        _ cmd: String, toolCallID: String, explanation: String,
        pane: PaneController, paneLabel: String, wasFallback: Bool,
        turns: inout [ConversationTurn]
    ) async {
        state = .executing(cmd: cmd)
        let uuid = UUID().uuidString.prefix(8)
        let sentinel = "__SIMPLETON_DONE_\(uuid)__"
        // Embed exit code in sentinel: __SIMPLETON_DONE_xxxx_EXIT_0__
        let fullCommand = "\(cmd)\n__simpleton_ec=$?; printf '\\n\(sentinel)_EXIT_%d__\\n' \"$__simpleton_ec\"; exit_unused=$__simpleton_ec\n"
        pane.terminalView.send(data: Array(fullCommand.utf8)[...])

        state = .capturingOutput
        let (output, exitCode) = await captureOutputWithExitCode(sentinel: sentinel, pane: pane)

        var result = ""
        if wasFallback {
            result += "[Note: Target pane was closed. Command ran on \(paneLabel) instead.]\n"
        }
        if let code = exitCode {
            result += "[exit code: \(code)]\n"
        }
        result += output
        onCommandExecuted?(cmd, result, paneLabel)
        turns.append(.toolResult(toolCallID: toolCallID, output: result))
    }

    private func captureOutputWithExitCode(sentinel: String, pane: PaneController) async -> (output: String, exitCode: Int?) {
        let terminal = pane.terminalView.getTerminal()
        let maxWait = 30_000
        let pollMs  = 200
        var elapsed = 0
        // Pattern: __SIMPLETON_DONE_xxxx_EXIT_N__
        let exitPattern = "\(sentinel)_EXIT_"

        while elapsed < maxWait && !isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(pollMs) * 1_000_000)
            elapsed += pollMs

            let rows = terminal.rows
            var lines: [String] = []
            for row in 0..<rows {
                if let line = terminal.getLine(row: row) {
                    lines.append(line.translateToString(trimRight: true))
                }
            }
            let buffer = lines.joined(separator: "\n")

            if let range = buffer.range(of: exitPattern) {
                let before = String(buffer[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                // Extract exit code number after _EXIT_
                let afterPrefix = String(buffer[range.upperBound...])
                let exitCode: Int?
                if let endRange = afterPrefix.range(of: "__") {
                    exitCode = Int(afterPrefix[..<endRange.lowerBound])
                } else {
                    exitCode = nil
                }
                return (before, exitCode)
            }

            // Fallback: check for sentinel without exit code (old format)
            if buffer.contains(sentinel) {
                if let range = buffer.range(of: sentinel) {
                    let before = String(buffer[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    return (before, nil)
                }
            }
        }
        return ("[Timed out waiting for command output after \(maxWait/1000)s]", nil)
    }

    // MARK: - System Prompts

    private func buildSystemPrompt(skill: Skill, params: [String: String], conversation: TabConversation, focusedPane: PaneController) -> String {
        var prompt = skill.systemPrompt
        for (key, value) in params {
            prompt = prompt.replacingOccurrences(of: "{\(key)}", with: value)
        }

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

    private func buildSystemPromptLegacy(skill: Skill, params: [String: String], pane: PaneController) -> String {
        var prompt = skill.systemPrompt
        for (key, value) in params {
            prompt = prompt.replacingOccurrences(of: "{\(key)}", with: value)
        }
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

    private func buildParamSummary(params: [String: String]) -> String {
        guard !params.isEmpty else { return "" }
        let list = params.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        return " Parameters: \(list)."
    }

    /// Extract pane number from tool call explanation.
    private func extractPaneNumber(from explanation: String) -> Int? {
        let pattern = "(?i)pane\\s*:?\\s*(\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: explanation, range: NSRange(location: 0, length: (explanation as NSString).length)),
              match.numberOfRanges >= 2 else { return nil }
        let numStr = (explanation as NSString).substring(with: match.range(at: 1))
        return Int(numStr)
    }
}
