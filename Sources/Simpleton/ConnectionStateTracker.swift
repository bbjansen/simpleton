// Sources/Simpleton/ConnectionStateTracker.swift
import Foundation
import SimpletonCore

/// Tracks SSH connection state by scanning terminal output for known prompt patterns.
final class ConnectionStateTracker {

    enum DetectedPrompt {
        case hostKeyVerification(fingerprint: String)
        case passwordPrompt
        case passphrasePrompt
        case verificationCode
        case connectionEstablished
        case connectionRefused
        case connectionTimeout
    }

    /// Called when a prompt is detected.
    var onPromptDetected: ((DetectedPrompt) -> Void)?

    /// Called when connection state changes.
    var onStateChange: ((PaneState) -> Void)?

    private var outputBuffer = ""
    private var hasAuthenticated = false

    /// Feed terminal output bytes for scanning. Call this from the PTY read callback.
    func feedOutput(_ text: String) {
        outputBuffer += text

        // Keep buffer from growing unbounded — only scan last 2KB
        if outputBuffer.count > 2048 {
            outputBuffer = String(outputBuffer.suffix(2048))
        }

        scanForPrompts()
    }

    /// Reset state for a new connection attempt.
    func reset() {
        outputBuffer = ""
        hasAuthenticated = false
    }

    /// Whether the connection has successfully authenticated at least once.
    var wasAuthenticated: Bool { hasAuthenticated }

    // MARK: - Pattern Scanning

    private func scanForPrompts() {
        let lower = outputBuffer.lowercased()

        // Host key verification
        if lower.contains("are you sure you want to continue connecting") {
            let fingerprint = extractFingerprint(from: outputBuffer)
            onPromptDetected?(.hostKeyVerification(fingerprint: fingerprint))
            outputBuffer = ""
            return
        }

        // Password prompt
        if lower.hasSuffix("password: ") || lower.hasSuffix("password:") {
            onPromptDetected?(.passwordPrompt)
            outputBuffer = ""
            return
        }

        // Passphrase prompt
        if lower.contains("enter passphrase for key") {
            onPromptDetected?(.passphrasePrompt)
            outputBuffer = ""
            return
        }

        // 2FA / verification code
        if lower.contains("verification code") || lower.contains("one-time password") {
            onPromptDetected?(.verificationCode)
            outputBuffer = ""
            return
        }

        // Connection refused
        if lower.contains("connection refused") {
            onPromptDetected?(.connectionRefused)
            onStateChange?(.disconnected)
            outputBuffer = ""
            return
        }

        // Connection timed out
        if lower.contains("connection timed out") || lower.contains("operation timed out") {
            onPromptDetected?(.connectionTimeout)
            onStateChange?(.disconnected)
            outputBuffer = ""
            return
        }

        // Detect successful connection — look for shell prompt patterns
        // After authentication, the remote shell will produce a prompt.
        // We detect this by looking for common prompt endings after auth prompts clear.
        if !hasAuthenticated && (lower.hasSuffix("$ ") || lower.hasSuffix("# ") || lower.hasSuffix("% ")) {
            hasAuthenticated = true
            onPromptDetected?(.connectionEstablished)
            onStateChange?(.running)
            outputBuffer = ""
        }
    }

    private func extractFingerprint(from text: String) -> String {
        // SSH fingerprint patterns: SHA256:xxx or MD5:xx:xx:xx
        let patterns = [
            #"SHA256:[A-Za-z0-9+/=]+"#,
            #"MD5:[0-9a-f:]{47}"#,
            #"ECDSA key fingerprint is [^\n]+"#,
            #"ED25519 key fingerprint is [^\n]+"#,
        ]

        for pattern in patterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                return String(text[range])
            }
        }
        return "(unknown fingerprint)"
    }
}
