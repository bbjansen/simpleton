// Sources/Simpleton/AI/WatchSession.swift
import Foundation
import SimpletonCore

@MainActor
final class WatchSession: ObservableObject {
    enum TriggerType {
        case exitCodeNonZero
        case outputPattern(String)
    }

    @Published var isActive = false

    private let pane: PaneController
    private let triggers: [TriggerType]
    private let aiService: AIService
    private let memoryStore: MemoryStore?
    private let onEvent: (String) -> Void
    private var pollTask: Task<Void, Never>?
    private var lastSeenOutput: String = ""
    private var lastSeenExitCode: Int32? = nil
    private var isPaused = false

    init(pane: PaneController, triggers: [TriggerType], aiService: AIService, memoryStore: MemoryStore? = nil, onEvent: @escaping (String) -> Void) {
        self.pane = pane
        self.triggers = triggers
        self.aiService = aiService
        self.memoryStore = memoryStore
        self.onEvent = onEvent
    }

    deinit {
        pollTask?.cancel()
    }

    func start() {
        guard !isActive else { return }
        isActive = true
        lastSeenOutput = currentTerminalOutput()
        lastSeenExitCode = pane.promptTracker.regions.last?.exitCode
        pollTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    func stop() {
        isActive = false
        pollTask?.cancel()
        pollTask = nil
    }

    func pause() { isPaused = true }
    func resume() { isPaused = false }

    // MARK: - Polling Loop

    private func pollLoop() async {
        while isActive && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard isActive, !isPaused else { continue }

            let currentOutput = currentTerminalOutput()
            guard currentOutput != lastSeenOutput else { continue }

            let newContent = extractNewContent(previous: lastSeenOutput, current: currentOutput)
            lastSeenOutput = currentOutput

            for trigger in triggers {
                if let matchResult = checkTrigger(trigger, newContent: newContent) {
                    await handleTrigger(matchResult: matchResult, newContent: newContent)
                    break
                }
            }
        }
    }

    // MARK: - Trigger Checking

    private enum TriggerMatch {
        case exitCode(Int32)
        case pattern(String, matched: String)
    }

    private func checkTrigger(_ trigger: TriggerType, newContent: String) -> TriggerMatch? {
        switch trigger {
        case .exitCodeNonZero:
            if let lastRegion = pane.promptTracker.regions.last,
               let exitCode = lastRegion.exitCode,
               exitCode != 0,
               exitCode != lastSeenExitCode {
                lastSeenExitCode = exitCode
                return .exitCode(exitCode)
            }
            let errorPatterns = ["error:", "Error:", "FAILED", "panic:", "Traceback", "Exception"]
            for pattern in errorPatterns {
                if newContent.contains(pattern) {
                    return .pattern(pattern, matched: pattern)
                }
            }
            return nil

        case .outputPattern(let regexStr):
            do {
                let regex = try NSRegularExpression(pattern: regexStr, options: [.caseInsensitive])
                let range = NSRange(newContent.startIndex..., in: newContent)
                if let match = regex.firstMatch(in: newContent, options: [], range: range) {
                    let matched = (newContent as NSString).substring(with: match.range)
                    return .pattern(regexStr, matched: matched)
                }
            } catch {
                print("[Watch] Invalid regex pattern '\(regexStr)': \(error.localizedDescription)")
            }
            return nil
        }
    }

    // MARK: - Trigger Handler

    private func handleTrigger(matchResult: TriggerMatch, newContent: String) async {
        let triggerDescription: String
        switch matchResult {
        case .exitCode(let code):
            triggerDescription = "Command exited with code \(code)"
        case .pattern(_, let matched):
            triggerDescription = "Pattern matched: \(matched)"
        }

        let recentOutput = String(newContent.suffix(2000))
        let prompt = PromptBuilder.buildWatchPrompt(trigger: triggerDescription, paneOutput: recentOutput)

        do {
            let response = try await aiService.complete(
                system: prompt,
                user: "Analyze the trigger event and provide a concise diagnosis with suggested next steps.",
                options: AIOptions(maxTokens: 1000, temperature: 0.3)
            )
            onEvent("[\(triggerDescription)]\n\n\(response)")
        } catch {
            onEvent("[\(triggerDescription)] Watch triggered but AI analysis failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func currentTerminalOutput() -> String {
        let terminal = pane.terminalView.getTerminal()
        let rows = terminal.rows
        var lines: [String] = []
        for row in 0..<rows {
            if let line = terminal.getLine(row: row) {
                lines.append(line.translateToString(trimRight: true))
            }
        }
        return lines.joined(separator: "\n")
    }

    private func extractNewContent(previous: String, current: String) -> String {
        if current.hasPrefix(previous) {
            return String(current.dropFirst(previous.count))
        }
        let prevLines = previous.components(separatedBy: "\n")
        let currLines = current.components(separatedBy: "\n")
        var divergeIndex = 0
        for i in 0..<min(prevLines.count, currLines.count) {
            if prevLines[i] != currLines[i] { break }
            divergeIndex = i + 1
        }
        if divergeIndex < currLines.count {
            return currLines[divergeIndex...].joined(separator: "\n")
        }
        return ""
    }
}
