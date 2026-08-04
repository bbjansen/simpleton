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

    t.suite("ShellIntegration.isBash") {
        t.expect(ShellIntegration.isBash("/bin/bash"), "/bin/bash is bash")
        t.expect(ShellIntegration.isBash("/opt/homebrew/bin/bash"), "homebrew bash")
        t.expect(!ShellIntegration.isBash("/bin/zsh"), "zsh is not bash")
    }

    t.suite("ShellIntegration.bashRcfile") {
        let s = ShellIntegration.bashRcfile
        t.expect(s.contains("]133;C"), "DEBUG trap emits command-start")
        t.expect(s.contains("]133;D;"), "PROMPT_COMMAND emits command-end with exit code")
        t.expect(s.contains("trap '__simpleton_preexec' DEBUG"), "installs DEBUG trap")
        t.expect(s.contains("PROMPT_COMMAND="), "chains PROMPT_COMMAND")
        t.expect(s.contains(".bash_profile"), "sources the user's login profile (no double-source)")
        t.expect(s.contains("*__simpleton_precmd*)"), "guards against re-adding to PROMPT_COMMAND")
    }

    t.suite("ShellIntegration.launchArgs") {
        t.expectEqual(
            ShellIntegration.launchArgs(shellPath: "/bin/bash", integrationEnabled: true, bashRcfilePath: "/x/rc"),
            ["--rcfile", "/x/rc"], "bash + integration → --rcfile")
        t.expectEqual(
            ShellIntegration.launchArgs(shellPath: "/bin/zsh", integrationEnabled: true, bashRcfilePath: "/x/rc"),
            ["-l"], "zsh keeps login shell (env-based injection)")
        t.expectEqual(
            ShellIntegration.launchArgs(shellPath: "/bin/bash", integrationEnabled: false, bashRcfilePath: "/x/rc"),
            ["-l"], "integration off → login shell")
    }
}
