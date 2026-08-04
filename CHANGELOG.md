# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project aims to follow
[Semantic Versioning](https://semver.org/).

## [0.1.2](https://github.com/bbjansen/simpleton/compare/v0.1.1...v0.1.2) (2026-08-04)


### Features

* **ai:** provider-agnostic AI with presets and live model selection ([#7](https://github.com/bbjansen/simpleton/issues/7)) ([77df043](https://github.com/bbjansen/simpleton/commit/77df043a3c90307599e343e73cb443d3a6b391de))


### Bug Fixes

* **prefs:** make the Skills list column resizable and wider by default ([7bc8b18](https://github.com/bbjansen/simpleton/commit/7bc8b18111a432a23a44965edba0ac49336ec727))

## [0.1.1] - 2026-08-04

First public alpha.

### Added
- Native macOS terminal built on AppKit + SwiftUI and SwiftTerm.
- Native window tabbing and arbitrarily nested split panes (split right/down, directional focus,
  pane zoom).
- SSH connection bookmarks with frecency ranking, `~/.ssh/config` import, keepalive, and
  auto-reconnect; connection sidebar with search.
- Optional AI copilot: per-tab AI chat, skills, and MCP tool support, gated by a command
  classifier that blocks destructive shell actions.
- Dockable panels: command history, environment, processes, Docker, notes, SSH tunnels, and more.
- Theme discovery, a plugin manager with lifecycle events, and user scripts.
- Resizable Preferences window covering General, Appearance, Terminal, SSH, Keys, Plugins, AI,
  Skills, and Profiles.
- `CoreChecks`, a dependency-free, no-Xcode test runner (250+ checks) plus a CI pipeline.

### Fixed
- Startup crash caused by coordinators initialising after the launch sequence.
- Keychain re-prompting on every launch (migration no longer resets the item ACL).
- SSH connections opening in the first tab instead of the active tab.
- Tab status dot not turning green once an SSH session became interactive.
- AI chat showing the previous tab's conversation.
- Panels reading configuration frozen at first display instead of the current settings.
- Session capture/restore of nested splits, extra tabs, and per-pane working directories.
- Several panel/preferences issues: stale writes, UI freezes, leaks, and an index crash.

### Changed
- Session restore is temporarily disabled while its prompt is reworked to be non-blocking.

[0.1.1]: https://github.com/bbjansen/simpleton/releases/tag/v0.1.1
