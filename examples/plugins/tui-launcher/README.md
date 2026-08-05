# TUI Launcher — example Simpleton plugin

Launches terminal TUIs (`top`, `lazygit`, `htop`) in a new pane from the Command Palette.
It demonstrates the **`open-pane`** action, which lets a script plugin open a pane running any
shell command — so a plugin's "UI" can be a real terminal TUI (Bubble Tea, Textual, ratatui,
`gum`/`fzf` scripts, or any binary it ships).

## How it works

A script plugin is a folder with a `plugin.json` manifest and an executable `entrypoint`.
Simpleton runs the entrypoint, writes a one-line JSON **context** (including the invoked
`commandId`) to its stdin, and reads newline-delimited JSON **actions** from its stdout.

This plugin replies with an `open-pane` action:

```json
{ "action": "open-pane", "command": "lazygit", "mode": "split-right" }
```

| field | meaning |
|---|---|
| `command` | shell command to run (runs in your real shell, so PATH/aliases work) |
| `mode` | `split-right` (default), `split-down`, or `tab` |

The pane returns to a normal prompt when the TUI exits. `open-pane` must be listed in the
manifest's `permissions`.

## Install

```bash
cp -R examples/plugins/tui-launcher \
  ~/Library/Application\ Support/Simpleton/scripts/
chmod +x ~/Library/Application\ Support/Simpleton/scripts/tui-launcher/run
```

Then **Preferences → Plugins → Reload Plugins**. The three `TUI:` commands appear in the
Command Palette; run one to open the TUI in a split pane. (`top` is built in; `lazygit`/`htop`
need to be installed.)
