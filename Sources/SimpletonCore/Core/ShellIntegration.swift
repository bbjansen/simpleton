// Sources/SimpletonCore/Core/ShellIntegration.swift
import Foundation

/// Generates shell-integration snippets that make the shell emit OSC 133 semantic-prompt
/// sequences (command start/end + exit code). These drive exit-status feedback (e.g. the red
/// pane flash on a failed command) and richer prompt tracking.
///
/// Opt-in and non-destructive: the injected `.zshenv` restores the user's real `ZDOTDIR` before
/// anything else, so their normal startup files load untouched, then appends OSC 133 hooks
/// (via `add-zsh-hook`, which coexists with existing `precmd`/`preexec` functions).
public enum ShellIntegration {

    /// True if the given shell path is zsh.
    public static func isZsh(_ shellPath: String) -> Bool {
        (shellPath as NSString).lastPathComponent == "zsh"
    }

    /// `.zshenv` placed in a Simpleton-owned `ZDOTDIR`. Read for every zsh invocation, so it is
    /// deliberately minimal and guards the interactive-only work.
    public static let zshZshenv = #"""
        # Simpleton shell integration — OSC 133 semantic prompts.
        # Auto-generated; safe to delete (regenerated on launch). Restores your real config first.
        if [[ -n "$SIMPLETON_USER_ZDOTDIR" ]]; then
          ZDOTDIR="$SIMPLETON_USER_ZDOTDIR"
        else
          unset ZDOTDIR
        fi
        [[ -f "${ZDOTDIR:-$HOME}/.zshenv" ]] && source "${ZDOTDIR:-$HOME}/.zshenv"

        if [[ -o interactive ]]; then
          autoload -Uz add-zsh-hook 2>/dev/null
          __simpleton_preexec() { printf '\e]133;C\a' }
          __simpleton_precmd() { printf '\e]133;D;%s\a\e]133;A\a' "$?" }
          add-zsh-hook preexec __simpleton_preexec 2>/dev/null
          add-zsh-hook precmd __simpleton_precmd 2>/dev/null
        fi
        """#
}
