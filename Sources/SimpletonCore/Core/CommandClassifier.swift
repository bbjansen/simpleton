// Sources/SimpletonCore/Core/CommandClassifier.swift
import Foundation

/// Classifies shell commands as read-only ("safe") or potentially side-effecting.
///
/// Used by the AI agent's "safe" autopilot tier to decide whether a command can be
/// auto-approved or must prompt the user. Lives in SimpletonCore (rather than the app
/// target) so it is unit-testable without Xcode.
public struct CommandClassifier {
    /// Read-only command prefixes considered safe to auto-run.
    public static let safePatterns: [String] = [
        "ls", "cat", "head", "tail", "wc", "file", "which", "whoami", "hostname",
        "pwd", "echo", "date", "uptime", "df", "du", "free", "top -l 1",
        "git status", "git log", "git diff", "git branch", "git remote",
        "docker ps", "docker images", "docker logs",
        "npm list", "npm outdated", "cargo check", "swift build",
        "env", "printenv", "id", "uname", "sw_vers",
        "curl -s", "ping -c", "dig", "nslookup", "traceroute",
        "find", "grep", "rg", "fd", "ag",
    ]

    /// Shell operators that can chain, redirect, or pipe into side-effecting commands.
    /// Any command containing one of these is never treated as safe.
    public static let unsafeOperators: [String] = ["|", ">", ">>", "<", "&&", "||", ";"]

    /// Command-substitution markers — these run arbitrary nested commands, so an
    /// otherwise safe-looking prefix (e.g. `echo`) can still execute anything.
    public static let unsafeSubstitutions: [String] = ["$(", "`"]

    /// Destructive action flags (chiefly for `find`) that delete files or execute
    /// other programs. `-exec` also covers `-execdir`, `-ok` covers `-okdir`, and
    /// `-fprint` covers `-fprintf`.
    public static let dangerousArguments: [String] = [
        " -delete", " -exec", " -ok", " -fprint", " -fls",
    ]

    /// True if `command` is a single read-only command with no shell operators,
    /// command substitution, or destructive action flags.
    public static func isSafe(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        for token in unsafeOperators + unsafeSubstitutions + dangerousArguments {
            if trimmed.contains(token) { return false }
        }
        return safePatterns.contains { pattern in
            trimmed == pattern || trimmed.hasPrefix(pattern + " ") || trimmed.hasPrefix(pattern + "\t")
        }
    }
}
