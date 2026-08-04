// Tests/CoreChecks/ShellIntegrationChecks.swift
import Foundation
import SimpletonCore

func runShellIntegrationChecks(_ t: TestRunner) {
    t.suite("ShellIntegration.isZsh") {
        t.expect(ShellIntegration.isZsh("/bin/zsh"), "/bin/zsh is zsh")
        t.expect(ShellIntegration.isZsh("/opt/homebrew/bin/zsh"), "homebrew zsh")
        t.expect(!ShellIntegration.isZsh("/bin/bash"), "bash is not zsh")
        t.expect(!ShellIntegration.isZsh("/usr/bin/fish"), "fish is not zsh")
    }

    t.suite("ShellIntegration.zshZshenvEmitsOSC133") {
        let s = ShellIntegration.zshZshenv
        t.expect(s.contains("]133;C"), "emits command-start (133;C)")
        t.expect(s.contains("]133;D;"), "emits command-end with exit code (133;D)")
        t.expect(s.contains("]133;A"), "emits prompt-start (133;A)")
        t.expect(s.contains("add-zsh-hook preexec"), "registers preexec hook")
        t.expect(s.contains("add-zsh-hook precmd"), "registers precmd hook")
    }

    t.suite("ShellIntegration.zshZshenvPreservesUserConfig") {
        let s = ShellIntegration.zshZshenv
        // Must restore the real ZDOTDIR and source the user's real .zshenv (non-destructive).
        t.expect(s.contains("SIMPLETON_USER_ZDOTDIR"), "restores the user's real ZDOTDIR")
        t.expect(s.contains("source \"${ZDOTDIR:-$HOME}/.zshenv\""), "sources the user's real .zshenv")
        t.expect(s.contains("[[ -o interactive ]]"), "guards hooks to interactive shells only")
    }
}
