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

    /// True if the given shell path is bash.
    public static func isBash(_ shellPath: String) -> Bool {
        (shellPath as NSString).lastPathComponent == "bash"
    }

    /// Shell launch args when integration is enabled. bash is injected via `--rcfile` (there is no
    /// ZDOTDIR equivalent); zsh and everything else keep the login shell (`-l`) and, for zsh, are
    /// handled through the environment (ZDOTDIR).
    public static func launchArgs(shellPath: String, integrationEnabled: Bool, bashRcfilePath: String) -> [String] {
        if integrationEnabled && isBash(shellPath) {
            return ["--rcfile", bashRcfilePath]
        }
        return ["-l"]
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

    /// bash init file (used via `bash --rcfile`). Replicates login config loading (sourcing the
    /// first of .bash_profile/.bash_login/.profile, matching `bash -l`, so nothing double-sources),
    /// then adds OSC 133 via a DEBUG trap (command start) and PROMPT_COMMAND (command end + prompt).
    public static let bashRcfile = #"""
        # Simpleton shell integration (bash) — OSC 133 semantic prompts.
        # Auto-generated; safe to delete (regenerated on launch). Loads your real config first.
        if [ -f "$HOME/.bash_profile" ]; then source "$HOME/.bash_profile"
        elif [ -f "$HOME/.bash_login" ]; then source "$HOME/.bash_login"
        elif [ -f "$HOME/.profile" ]; then source "$HOME/.profile"
        fi

        __simpleton_preexec() { printf '\e]133;C\a'; }
        trap '__simpleton_preexec' DEBUG
        __simpleton_precmd() { local __ec=$?; printf '\e]133;D;%s\a\e]133;A\a' "$__ec"; }
        case "$PROMPT_COMMAND" in
          *__simpleton_precmd*) ;;
          *) PROMPT_COMMAND="__simpleton_precmd${PROMPT_COMMAND:+; $PROMPT_COMMAND}" ;;
        esac
        """#
}
