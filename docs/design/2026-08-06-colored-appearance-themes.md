# Colored Appearance Themes — Design

## Overview

Add a small set of curated, premium built-in color themes selectable in **Settings → Appearance**.
A theme recolors the **whole app** — terminal palette, UI chrome (sidebar / panels / tabs / borders),
and the accent — as one cohesive look. This *extends* the existing native Dark / Light / Auto + accent
model rather than replacing it: Dark, Light, and Auto remain as neutral entries; the colored themes are
added to the same picker. Switching is **live** (no relaunch), matching how the accent already switches.

## Goals

- Five colored themes: **Tokyo Night, Nord, Dracula, Gruvbox, Catppuccin Mocha**.
- Whole-app theming — terminal + chrome + accent, cohesive.
- Live / instant switching, no relaunch.
- Neutral **Dark / Light / Auto** preserved **exactly** — no visual change for existing users.
- A single unified theme picker; the accent dropdown shows only for the neutral themes (a colored
  theme carries its own accent).

## Non-goals (YAGNI)

- User-editable / custom themes.
- Importing external formats (iTerm2, VS Code, base16).
- Per-theme dark **and** light variants — each colored theme is a single fixed palette.
- More than the five curated themes (the model stays open to adding more later).

## The theme set

| id | name | isDark | background | foreground | accent |
|---|---|---|---|---|---|
| `tokyo-night` | Tokyo Night | yes | `#1A1B26` | `#C0CAF5` | `#7AA2F7` |
| `nord` | Nord | yes | `#2E3440` | `#D8DEE9` | `#88C0D0` |
| `dracula` | Dracula | yes | `#282A36` | `#F8F8F2` | `#BD93F9` |
| `gruvbox` | Gruvbox | yes | `#282828` | `#EBDBB2` | `#FE8019` |
| `catppuccin` | Catppuccin Mocha | yes | `#1E1E2E` | `#CDD6F4` | `#CBA6F7` |

Plus neutral `dark`, `light`, and `auto` (auto resolves to `dark`/`light` by system appearance).

## Data model

- **`ThemeColors`** (existing, `SimpletonCore/Models/Theme.swift`) — unchanged. The terminal palette:
  background, foreground, cursor, selection, 16 ANSI colors, sidebar, tabBar, splitBorder.
- **`ChromeColors`** (new struct) — the UI-chrome tokens currently hardcoded in `DesignTokens`:
  base, surface, elevated, hover, selected, border, panelBorder, and text tiers
  (primary, secondary, tertiary, muted, faint). Capturing all of them keeps the neutral Dark/Light
  presets pixel-identical to today.
- **`Theme`** (new struct): `{ id: String, name: String, isDark: Bool, terminal: ThemeColors,
  chrome: ChromeColors, accent: String /* hex */ }`.
- **`ThemePalette`** (new): static presets `.dark`, `.light` (reproduce today's `DesignTokens` +
  `ThemeColors` values exactly), `.tokyoNight`, `.nord`, `.dracula`, `.gruvbox`, `.catppuccin`;
  plus `all: [Theme]` and `resolve(id: String) -> Theme` (unknown id → `.dark`).

## Config + migration

- `AppConfig.appearance.appearanceMode` (String) now doubles as the **theme id**. Existing values
  `"dark"` / `"light"` / `"auto"` stay valid; the colored ids are added. No schema change and no
  migration code — decode is already tolerant, and unknown ids fall back to `dark` at resolve time.
- `accentColor` still applies to `dark` / `light` / `auto`. For a colored theme it is ignored
  (`theme.accent` wins).

## Architecture / components

- **`ThemeSettings`** (existing `ObservableObject`, `Views/AppTheme.swift`) — gains
  `@Published var theme: Theme` as the single source of truth for the active theme, observed by
  SwiftUI. (Keeps `accentID` for the neutral accent path.)
- **`AppTheme.update(from:)`** — resolves the active theme, sets `ThemeSettings.shared.theme`, sets
  `accentNSColor` (colored theme → `theme.accent`; neutral → `AccentPalette` from `accentColor`), and
  sets `NSApp.appearance` from `theme.isDark`. `auto` is handled here (not in `ThemePalette`): it maps
  to the `dark` or `light` preset by the current system appearance and leaves `NSApp.appearance = nil`
  so it keeps following the system. Concrete ids resolve directly via `ThemePalette.resolve`.
- **`DesignTokens`** — the one substantial refactor: each chrome `Color` reads
  `ThemeSettings.shared.theme.chrome.*` instead of `dyn(light,dark)`, converting the stored hex with
  the same hex→`NSColor` helper `ThemeColors` already uses for terminal colors.
- **`ThemeApplier`** — terminal palette comes from `ThemeSettings.shared.theme.terminal` instead of
  the `isLight ? .light : .dark` pick; caret / selection from `theme.accent`.
- **Appearance settings tab** (`Views/PreferencesWindow.swift`) — the appearance control becomes a
  single **Theme** picker over `ThemePalette.all` (Dark / Light / Auto, then the colored themes).
  The accent dropdown is shown only when the selected theme is neutral.
- **`AppDelegate`** — on theme change (config save): `AppTheme.update` → `applyConfigToAllPanes()`
  (re-applies terminal + window background) → bump the root SwiftUI view's `.id(themeID)` so
  chrome-consuming views rebuild against the new tokens.

## Data flow

```
config.appearanceMode (themeID)
      │  AppTheme.update(from:)
      ▼
ThemeSettings.theme (@Published) ─┬─▶ DesignTokens.chrome.*     (SwiftUI chrome)
NSApp.appearance (isDark)         ├─▶ ThemeApplier.terminal.*   (AppKit terminal)
accentNSColor                     └─▶ AppTheme.accent / .tint   (focus ring, cursor, highlights)
```

On a user change in Settings, the Appearance tab writes `config.appearanceMode`; `onChanged` routes to
`AppDelegate`, which applies the flow above and triggers the live recolor.

## Live switching mechanism

- **SwiftUI chrome:** the root content view carries `.id(themeSettings.themeID)`; changing the id
  rebuilds the subtree, which re-reads the now-theme-driven `DesignTokens`. Views already observing
  `ThemeSettings` (accent) update regardless.
- **AppKit surfaces** (terminal colors, window `backgroundColor`, split borders): re-applied
  imperatively through the existing `applyConfigToAllPanes()` + `WindowController.dissolveTitleBar`
  path.

## Error handling

- Unknown theme id → `ThemePalette.resolve` returns `.dark`.
- Invalid hex would yield a safe `Color(hex:)` fallback, but presets are compile-time constants and are
  validated by a CoreChecks test, so this can't happen at runtime.
- Auto with no resolvable system appearance → default to the dark preset.

## Testing (CoreChecks, no-Xcode runner)

- Every `ThemePalette` preset: all hex strings parse; `isDark` matches background luminance; terminal
  has all 16 ANSI colors + bg/fg; chrome has every required field.
- `resolve(id:)`: known ids map correctly; unknown → `dark`.
- Neutral `dark` / `light` presets equal the pre-refactor `DesignTokens` + `ThemeColors` values
  (guards against drift so existing users see no change).
- Accent resolution: colored theme → `theme.accent`; neutral → `accentColor`.

## File-level changes

- `Sources/SimpletonCore/Models/Theme.swift` — add `ChromeColors` and `Theme` (keep `ThemeColors`).
- `Sources/SimpletonCore/Models/ThemePalette.swift` (new) — the seven presets + `resolve` / `all`.
- `Sources/Simpleton/Views/AppTheme.swift` — `ThemeSettings.@Published theme`; theme/accent resolution.
- `Sources/Simpleton/Views/DesignTokens.swift` — chrome reads the active theme.
- `Sources/Simpleton/ThemeApplier.swift` — terminal from `theme.terminal`.
- `Sources/Simpleton/Views/PreferencesWindow.swift` — unified theme picker + conditional accent.
- `Sources/Simpleton/AppDelegate.swift` — theme-change re-apply + root `.id`.
- root content view — `.id(themeID)`.
- `Tests/CoreChecks/` — theme presets + resolution + drift tests.
