// Sources/Simpleton/SSHReconnectManager.swift
import Foundation
import SimpletonCore

/// Manages SSH auto-reconnection with exponential backoff.
/// Extracted from PaneController to isolate reconnection state and logic.
final class SSHReconnectManager {
    private var attempts = 0
    private var timer: Timer?
    private let maxAttempts: Int
    private let autoReconnect: Bool

    init(config: AppConfig) {
        self.maxAttempts = config.ssh.maxReconnectAttempts
        self.autoReconnect = config.ssh.autoReconnect
    }

    /// Start an auto-reconnect cycle with exponential backoff.
    /// - Parameters:
    ///   - onReconnect: Called when the backoff timer fires and reconnection should be attempted.
    ///   - onShowBanner: Called to display a reconnecting banner with the current attempt and delay.
    ///   - onExhausted: Called when auto-reconnect is disabled or max attempts have been reached.
    func start(
        onReconnect: @escaping () -> Void,
        onShowBanner: @escaping (_ attempt: Int, _ delay: Double) -> Void,
        onExhausted: @escaping () -> Void
    ) {
        guard autoReconnect, attempts < maxAttempts else {
            onExhausted()
            return
        }
        attempts += 1
        let delay = min(pow(2.0, Double(attempts - 1)), 30.0)
        onShowBanner(attempts, delay)
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            onReconnect()
        }
    }

    /// Cancel any pending reconnect timer.
    func cancel() {
        timer?.invalidate()
        timer = nil
    }

    /// Reset the attempt counter and cancel any pending timer.
    func reset() {
        attempts = 0
        cancel()
    }

    deinit { cancel() }
}
