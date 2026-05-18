// Sources/Simpleton/AI/ActiveAIHint.swift
import Foundation
import SimpletonCore

/// Generates lightweight AI-powered error explanations when a terminal command
/// fails (non-zero exit code detected via OSC 133).  Rate-limited to avoid
/// spamming the user with hints on repeated failures.
final class ActiveAIHint {

    /// Result returned on successful hint generation.
    struct Hint {
        let text: String
        let exitCode: Int32
        let paneID: PaneID
    }

    // MARK: - Rate Limiting

    /// Per-pane timestamp of the last hint shown, used to enforce the cooldown.
    private var lastHintTime: [PaneID: Date] = [:]

    /// Minimum interval between hints for the same pane (seconds).
    private let cooldown: TimeInterval = 10

    // MARK: - Public API

    /// Request an AI hint for a failed command.  Returns `nil` when rate-limited,
    /// AI is disabled, or the call fails.
    ///
    /// - Parameters:
    ///   - paneID: The pane that triggered the failure.
    ///   - exitCode: The non-zero exit code from OSC 133 `D;exitCode`.
    ///   - recentOutput: The last ~50 lines of terminal output for context.
    ///   - aiService: The shared AI service to call.
    /// - Returns: A `Hint` containing the explanation text, or `nil`.
    func requestHint(
        paneID: PaneID,
        exitCode: Int32,
        recentOutput: String,
        aiService: AIService
    ) async -> Hint? {
        guard aiService.isEnabled else { return nil }

        // Rate limit: skip if a hint was shown for this pane within the cooldown.
        let now = Date()
        if let last = lastHintTime[paneID], now.timeIntervalSince(last) < cooldown {
            return nil
        }

        let systemPrompt = """
            You are a concise terminal assistant embedded in a macOS terminal app. \
            A command just failed. Explain the error in one sentence, then suggest \
            a fix in one sentence. Keep your total response under 200 characters.
            """

        let userPrompt = """
            Exit code: \(exitCode)
            Recent terminal output:
            \(recentOutput.suffix(1500))
            """

        let options = AIOptions(maxTokens: 200, temperature: 0.3)

        do {
            let response = try await aiService.complete(
                system: systemPrompt,
                user: userPrompt,
                options: options
            )
            let trimmed = String(response.prefix(200))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmed.isEmpty else { return nil }

            lastHintTime[paneID] = now
            return Hint(text: trimmed, exitCode: exitCode, paneID: paneID)
        } catch {
            // Silently swallow — hints are best-effort.
            return nil
        }
    }

    /// Remove stale rate-limit entries for panes that no longer exist.
    func purgePane(_ paneID: PaneID) {
        lastHintTime.removeValue(forKey: paneID)
    }
}
