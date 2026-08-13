# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project aims to follow
[Semantic Versioning](https://semver.org/).

## [0.1.4](https://github.com/bbjansen/simpleton/compare/v0.1.3...v0.1.4) (2026-08-13)


### Features

* **connections:** add ConnectionStore actor with change notification ([51dc54f](https://github.com/bbjansen/simpleton/commit/51dc54f9192b86be65e4cd09412e6cd327ac68da))
* **connections:** add generic Connection model + kinds + secret ([9c00cb7](https://github.com/bbjansen/simpleton/commit/9c00cb72b882f002535b7296561d3ca19bc1e810))
* **connections:** add Keychain-backed CredentialStore ([a92b872](https://github.com/bbjansen/simpleton/commit/a92b87238826497e7ea51fe077d61857e787ea8f))
* **panels:** add ClientPanelScaffold shared chrome for tool panels ([691bc2b](https://github.com/bbjansen/simpleton/commit/691bc2b59c0bd6d9de3f4e7e6e49593684e5855a))

## [0.1.3](https://github.com/bbjansen/simpleton/compare/v0.1.2...v0.1.3) (2026-08-07)


### Features

* **ai:** surface provider error details (model + message) ([f691c28](https://github.com/bbjansen/simpleton/commit/f691c28b774865a1ebfad7cbbf7b3a3808d749e3))
* **header:** add Slack-style window header ([baac066](https://github.com/bbjansen/simpleton/commit/baac0663ddc7a650605b491599349f8cd15ecda9))
* **header:** collapse the omnibox to a search icon below ~820px width ([622193b](https://github.com/bbjansen/simpleton/commit/622193b1b1b749cb9c90ba9d58adb9ff1c74cb0f))
* **plugins:** open-pane action — launch terminal TUIs in a pane ([943af3e](https://github.com/bbjansen/simpleton/commit/943af3ed26b92b330c41d930bec216eee502a578))
* **prefs:** give the Settings window the app's dissolved-glass chrome ([faca94d](https://github.com/bbjansen/simpleton/commit/faca94dcde30dd533f37582fdc11979ebd267192))
* **sidebar:** remove the search field, pin Add Connection to the bottom ([531f647](https://github.com/bbjansen/simpleton/commit/531f64766ec25209e130e35bec5c558eb16aa471))
* **tabs:** make the active tab clearly focused (accent bar + elevated fill) ([ebb246b](https://github.com/bbjansen/simpleton/commit/ebb246b037da7e989db2bcab013fb375b3a68a10))
* **tabs:** replace native macOS window tabbing with custom in-app tabs ([695e17c](https://github.com/bbjansen/simpleton/commit/695e17c708957b2bcec8956f638f80be60f7b0df))
* **terminal:** extend shell integration to bash (OSC 133) ([#18](https://github.com/bbjansen/simpleton/issues/18)) ([93a052b](https://github.com/bbjansen/simpleton/commit/93a052be6b0fcb5897c94526a9b1215dce9ee57b))
* **terminal:** opt-in zsh shell integration (OSC 133) ([#16](https://github.com/bbjansen/simpleton/issues/16)) ([f13a751](https://github.com/bbjansen/simpleton/commit/f13a751ad92c77b577cc2a64fae32be2ae08fe6c))
* **themes:** add chrome-translucency control (frosted glass) ([9bd2c91](https://github.com/bbjansen/simpleton/commit/9bd2c91c0730b75ee549a6cae8e33a2c020fc182))
* **themes:** add ChromeColors + AppearanceTheme models ([3dd04df](https://github.com/bbjansen/simpleton/commit/3dd04dff6e7db9433c4588163eaa156c807cdc05))
* **themes:** add gradient (mixed-hue) themes — Sunset, Ember, Nebula ([eb6eea1](https://github.com/bbjansen/simpleton/commit/eb6eea1c1cc20fdeeca2458f652d9b20e4ad5e8a))
* **themes:** add six more pop-out themes (Teal, Indigo, Crimson, Magenta, Gold, Slate) ([93f7da9](https://github.com/bbjansen/simpleton/commit/93f7da9bf823e224c586633ae0a8033af1122118))
* **themes:** add ThemePalette with 7 presets (dark/light + 5 colored) ([f38d547](https://github.com/bbjansen/simpleton/commit/f38d5470b72a561722c3904734ea2583fd6931ee))
* **themes:** apply terminal palette from the active theme ([c924c55](https://github.com/bbjansen/simpleton/commit/c924c551c5c062bfee9e4f97c2152aed8d4978a4))
* **themes:** drive DesignTokens chrome + accent from the active theme ([20b5e48](https://github.com/bbjansen/simpleton/commit/20b5e4855df8faec5016b7b960af5e5129879f15))
* **themes:** observe ThemeSettings in remaining chrome panels for live theme switching ([0c5805f](https://github.com/bbjansen/simpleton/commit/0c5805fde753d6b6ae6f81372eae6010b325179f))
* **themes:** replace muted developer palettes with saturated Slack-style pop-out themes ([d0695c9](https://github.com/bbjansen/simpleton/commit/d0695c9a6e2be6339201ccb7d864300e32624336))
* **themes:** resolve active AppearanceTheme in AppTheme + publish on ThemeSettings ([25acbce](https://github.com/bbjansen/simpleton/commit/25acbce7239115ab1677cd9c4aa9e0e59ca46ba0))
* **themes:** theme the Settings forms with the active theme ([af4557f](https://github.com/bbjansen/simpleton/commit/af4557f8de20adb55af519c005d289dc9c9a9fe4))
* **themes:** unified theme picker with conditional accent in Appearance settings ([9abecd8](https://github.com/bbjansen/simpleton/commit/9abecd820a7c38ae322b60cc1c9ea85437f60316))
* **themes:** wire live theme switching through applyConfigToAllPanes ([b675410](https://github.com/bbjansen/simpleton/commit/b6754105789e09b154b750ba79e144fcf99fdd18))
* **ui:** adopt Liquid Glass on macOS 26, gated (P5) ([ec5e8fb](https://github.com/bbjansen/simpleton/commit/ec5e8fb14fb1354ca07cfc927ef4b78efb873375))
* **ui:** flash the pane red on a failed command (P4b, exit-status cue) ([#15](https://github.com/bbjansen/simpleton/issues/15)) ([3c79b66](https://github.com/bbjansen/simpleton/commit/3c79b6605f69476149c543f9c623f5095ae08401))
* **ui:** frosted-glass command palette and quick connect (P3) ([ce44d22](https://github.com/bbjansen/simpleton/commit/ce44d2216b81000f9c67cfa8ea9616a089b3f871))
* **ui:** pane right-click split/close menu + hoist Add Connection to sidebar top ([d8570b8](https://github.com/bbjansen/simpleton/commit/d8570b88fb818414a126d64c12d073ab3562d192))
* **ui:** premium dark redesign + native Dark/Light/Auto theming ([019b0b8](https://github.com/bbjansen/simpleton/commit/019b0b8ef26c0c4c1dbc05a8756c28ecd60b26aa))
* **ui:** snappy motion + hierarchical SF Symbols (P4a) ([aac6fde](https://github.com/bbjansen/simpleton/commit/aac6fde89d6b3f6ad859b475a671e0ee8fcf4049))
* **ui:** system-accent active-pane border + dim inactive panes (P2) ([040cd7a](https://github.com/bbjansen/simpleton/commit/040cd7a3d884224c01f38034c3acd6d850ef44ad))
* **ui:** translucent vibrancy chrome (P1) ([73359c3](https://github.com/bbjansen/simpleton/commit/73359c36fa6fc0a1ba4f994a08137e35a4d093e4))
* **workspaces:** bundle theme/profile/plugins with the layout + apply on open ([2a8c3ce](https://github.com/bbjansen/simpleton/commit/2a8c3ce345403468cfe30cf6ddcdd6185f1bbe31))
* **workspaces:** deeper prefs, replace-mode, defaults, rename/duplicate, auto-sync ([8d99da3](https://github.com/bbjansen/simpleton/commit/8d99da3f15b2fe9cec6af4d38246a21f79ce7579))
* **workspaces:** header switcher + Settings editor for switchable setups ([a8436a8](https://github.com/bbjansen/simpleton/commit/a8436a8933900311d8d1795773b2071d87670211))


### Bug Fixes

* **dialogs:** clean up the command palette + quick connect floating panels ([74678a7](https://github.com/bbjansen/simpleton/commit/74678a7368fc1cece1f1c959336f37e2f2edde8d))
* **header:** ground the header bar + close the top transparent strip ([eb2c67b](https://github.com/bbjansen/simpleton/commit/eb2c67b4f46238f1bb7517aa44116b5c3278f404))
* **header:** vertically center the traffic lights in the 46px header ([23398ea](https://github.com/bbjansen/simpleton/commit/23398ea622da14a29288ae7f6ee30de3391f0a69))
* **keychain:** reliable upsert store, key caching, and silent dev signing ([73e5382](https://github.com/bbjansen/simpleton/commit/73e53827d6da3bd8b8077de429099ac25c4ce15c))
* **palette:** run window-targeting commands against the terminal, not the palette ([918c7ba](https://github.com/bbjansen/simpleton/commit/918c7baace46209d8c4239d9c9aed1deb122d86c))
* **prefs:** apply window opacity and show it as a percentage ([#10](https://github.com/bbjansen/simpleton/issues/10)) ([4582653](https://github.com/bbjansen/simpleton/commit/458265324b337bc4cd18e349a7076187cc8547e1))
* **split:** mount the pane container as the initial root, not the raw terminal ([55a7360](https://github.com/bbjansen/simpleton/commit/55a73608d7217eb0626be1a0d442298c3b0f2134))
* **terminal:** parse OSC 7 file:// CWD into a plain path ([#20](https://github.com/bbjansen/simpleton/issues/20)) ([028bbd7](https://github.com/bbjansen/simpleton/commit/028bbd7afbd4210561641216cfde62a6471861ee))
* **themes:** chrome accent follows the active theme, not a stuck indigo placeholder ([7a1a603](https://github.com/bbjansen/simpleton/commit/7a1a603778aa715b0f1557a77b11803d2b67cc08))
* **themes:** complete live-switch sync + gradient backdrop + mono-font/divider polish ([6228e53](https://github.com/bbjansen/simpleton/commit/6228e534dd1807eca62263d3c92cdbe9981ce44e))
* **themes:** force immediate chrome repaint on theme switch (window.appearance + needsLayout/display + displayIfNeeded) so panels sync without a focus event ([038339a](https://github.com/bbjansen/simpleton/commit/038339a7a1074d1aa3ea3afe830f0a7c653972ce))
* **themes:** high-contrast section headings on the sidebar + panels ([87741d6](https://github.com/bbjansen/simpleton/commit/87741d6737c5fccb1d70324777f217c000cf39a8))
* **themes:** sync all panels on live theme switch ([fae6d9a](https://github.com/bbjansen/simpleton/commit/fae6d9a0e0e29cedfff559b3b405218b3bf5464c))
* **themes:** theme every dock panel so it syncs on a live theme switch ([4aa5946](https://github.com/bbjansen/simpleton/commit/4aa59469a28ffa33d6672992f68670d93bd09478))
* **themes:** theme the side-panel backdrop, Preferences window, and sidebar search field ([6b1c0e9](https://github.com/bbjansen/simpleton/commit/6b1c0e9ac2a7903538c6d76e6c68ca9c34dc0645))
* **themes:** theme-tinted glass chrome so each theme is fully its color (not neutral system material) ([2220b82](https://github.com/bbjansen/simpleton/commit/2220b82a2399cbf4edc47f772a4e3952beb35678))
* **themes:** titlebar + background-tab terminals follow the active theme; fix stale comment ([f4c0020](https://github.com/bbjansen/simpleton/commit/f4c00208e45e34bb0280ab015547d6be4b867a8d))
* **ui:** command palette / quick connect arrow-key + enter navigation ([365b31b](https://github.com/bbjansen/simpleton/commit/365b31bf0d04134965aa90644c5d26e6efba7a44))
* **ui:** command palette & quick connect never opened; dismiss on click-away ([2d6d874](https://github.com/bbjansen/simpleton/commit/2d6d874e1bf254c1e8073fefc11a187777f0164e))
* **ui:** keep windows opaque + legible frosted Material chrome ([af26ca6](https://github.com/bbjansen/simpleton/commit/af26ca68edc0a830c137b4c52fdd7acffa11bd6b))
* **ui:** light-mode consistency across panels + new-tab terminal palette ([38c22e7](https://github.com/bbjansen/simpleton/commit/38c22e7ef1e042cab94818779faf6f898d944b22))
* **ui:** quick connect select now connects (target the main terminal window) ([585b2ba](https://github.com/bbjansen/simpleton/commit/585b2ba741d27177e49c38a1488c7fcea075ea0a))

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
