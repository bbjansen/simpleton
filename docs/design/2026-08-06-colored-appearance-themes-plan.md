# Colored Appearance Themes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add five curated built-in color themes (Tokyo Night, Nord, Dracula, Gruvbox, Catppuccin Mocha) that recolor the whole app — terminal + chrome + accent — selectable in Settings → Appearance, switching live.

**Architecture:** Introduce an `AppearanceTheme` value (terminal `ThemeColors` + new `ChromeColors` + accent hex) with static presets in `SimpletonCore`. Make the app-side `DesignTokens` (chrome) and `ThemeApplier` (terminal) read the *active* theme from `ThemeSettings` instead of hardcoded dark/light. Neutral Dark/Light/Auto stay as presets that reproduce today's exact values. Live switching rides the existing `@Published`-observed-`ThemeSettings` + `applyConfigToAllPanes()` paths.

**Tech Stack:** Swift 6 / SPM (no Xcode), AppKit + SwiftUI + SwiftTerm. Two modules: `SimpletonCore` (models — `ThemeColors`, new `ChromeColors`/`AppearanceTheme`/`ThemePalette`) and `Simpleton` (app — `DT`, `AppTheme`, `ThemeSettings`, `ThemeApplier`, prefs). Unit checks run in the `CoreChecks` executable target (`swift run CoreChecks`), which depends on `SimpletonCore` only.

## Global Constraints

- No Xcode: build with `swift build`; unit checks via `swift run CoreChecks` (plain-executable `TestRunner`, `t.expect(...)` / `t.expectEqual(...)`). XCTest is unavailable.
- Only `SimpletonCore` public API is testable in `CoreChecks` (plain `import SimpletonCore`, no `@testable`). App-target types (`DT`, `AppTheme`, `ThemeApplier`, views) are verified by build + manual smoke, not unit tests.
- Hex is always 6-digit `#RRGGBB`. Reuse the existing `NSColor(hex:)` (`Sources/Simpleton/ThemeApplier.swift`) and `Color(hex:)` (`Sources/Simpleton/Views/SidebarView.swift`) — do not add new hex parsers.
- Neutral **Dark** and **Light** presets MUST reproduce today's exact values (the hex in `DesignTokens` comments and `ThemeColors.dark/.light`) so existing users see no change.
- Commit messages: conventional, imperative, no co-author/attribution lines.
- Colored themes are all `isDark: true`; they do NOT flip `NSApp.appearance` (stays `.darkAqua`).

---

### Task 1: `ChromeColors` + `AppearanceTheme` models (SimpletonCore)

**Files:**
- Modify: `Sources/SimpletonCore/Models/Theme.swift` (append the two structs after `ThemeColors`)
- Test: `Tests/CoreChecks/AppearanceThemeChecks.swift` (create)
- Modify: `Tests/CoreChecks/main.swift` (register the new suite)

**Interfaces:**
- Produces:
  - `struct ChromeColors: Codable, Equatable` with `public var` String fields: `base, surface, elevated, hover, selected, border, panelBorder, textPrimary, textSecondary, textTertiary, textMuted, textFaint, textHelp` and a memberwise `public init` (all params required).
  - `struct AppearanceTheme: Codable, Equatable, Identifiable` with `public let id: String; public let name: String; public let isDark: Bool; public var terminal: ThemeColors; public var chrome: ChromeColors; public var accent: String` and a memberwise `public init`.

- [ ] **Step 1: Write the failing test**

Create `Tests/CoreChecks/AppearanceThemeChecks.swift`:
```swift
// Tests/CoreChecks/AppearanceThemeChecks.swift
import Foundation
import SimpletonCore

func runAppearanceThemeChecks(_ t: TestRunner) {
    t.suite("AppearanceTheme.roundTrip") {
        let chrome = ChromeColors(
            base: "#0E0E11", surface: "#131316", elevated: "#191A1E", hover: "#1D1E22",
            selected: "#232429", border: "#26262B", panelBorder: "#1E1E22",
            textPrimary: "#F5F6F6", textSecondary: "#C7CBD1", textTertiary: "#8A8F98",
            textMuted: "#62666D", textFaint: "#4A4D54", textHelp: "#6A6E76")
        let theme = AppearanceTheme(
            id: "dark", name: "Dark", isDark: true,
            terminal: ThemeColors(), chrome: chrome, accent: "#5E6AD2")
        do {
            let data = try JSONEncoder().encode(theme)
            let decoded = try JSONDecoder().decode(AppearanceTheme.self, from: data)
            t.expectEqual(decoded, theme, "AppearanceTheme survives JSON round-trip")
            t.expectEqual(decoded.chrome.base, "#0E0E11", "chrome.base")
            t.expectEqual(decoded.accent, "#5E6AD2", "accent")
            t.expectEqual(decoded.id, "dark", "id")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }
}
```

Register it in `Tests/CoreChecks/main.swift` — add after `runThemeChecks(runner)`:
```swift
runAppearanceThemeChecks(runner)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift run CoreChecks 2>&1 | tail -20`
Expected: FAIL to **compile** — `cannot find 'ChromeColors' in scope` / `cannot find 'AppearanceTheme' in scope`.

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/SimpletonCore/Models/Theme.swift` (after the `ThemeColors` extension, before `Theme`/`ThemeFile` or at end of file):
```swift
/// UI-chrome colors for a whole-app theme — the tokens `DesignTokens` renders (sidebar, panels,
/// borders, text tiers). Stored as `#RRGGBB` hex, mirroring `ThemeColors`.
public struct ChromeColors: Codable, Equatable {
    public var base: String
    public var surface: String
    public var elevated: String
    public var hover: String
    public var selected: String
    public var border: String
    public var panelBorder: String
    public var textPrimary: String
    public var textSecondary: String
    public var textTertiary: String
    public var textMuted: String
    public var textFaint: String
    public var textHelp: String

    public init(
        base: String, surface: String, elevated: String, hover: String, selected: String,
        border: String, panelBorder: String, textPrimary: String, textSecondary: String,
        textTertiary: String, textMuted: String, textFaint: String, textHelp: String
    ) {
        self.base = base; self.surface = surface; self.elevated = elevated
        self.hover = hover; self.selected = selected; self.border = border
        self.panelBorder = panelBorder; self.textPrimary = textPrimary
        self.textSecondary = textSecondary; self.textTertiary = textTertiary
        self.textMuted = textMuted; self.textFaint = textFaint; self.textHelp = textHelp
    }
}

/// A whole-app appearance theme: terminal palette + UI chrome + accent, all in one value.
public struct AppearanceTheme: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let isDark: Bool
    public var terminal: ThemeColors
    public var chrome: ChromeColors
    public var accent: String  // #RRGGBB

    public init(
        id: String, name: String, isDark: Bool,
        terminal: ThemeColors, chrome: ChromeColors, accent: String
    ) {
        self.id = id; self.name = name; self.isDark = isDark
        self.terminal = terminal; self.chrome = chrome; self.accent = accent
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift run CoreChecks 2>&1 | tail -20`
Expected: PASS — `AppearanceTheme.roundTrip` checks pass, overall `✓ CoreChecks: all N checks passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/SimpletonCore/Models/Theme.swift Tests/CoreChecks/AppearanceThemeChecks.swift Tests/CoreChecks/main.swift
git commit -m "feat(themes): add ChromeColors + AppearanceTheme models"
```

---

### Task 2: `ThemePalette` — the seven presets (SimpletonCore)

**Files:**
- Create: `Sources/SimpletonCore/Models/ThemePalette.swift`
- Test: `Tests/CoreChecks/ThemePaletteChecks.swift` (create)
- Modify: `Tests/CoreChecks/main.swift`

**Interfaces:**
- Consumes: `ChromeColors`, `AppearanceTheme`, `ThemeColors` (Task 1 + existing).
- Produces:
  - `enum ThemePalette` with `public static let dark, light, tokyoNight, nord, dracula, gruvbox, catppuccin: AppearanceTheme`
  - `public static let all: [AppearanceTheme]` (order: dark, light, then the five colored)
  - `public static func resolve(_ id: String) -> AppearanceTheme` (case-insensitive; unknown → `dark`). `resolve("auto")` returns `dark` (the caller, `AppTheme.update`, handles auto by picking dark/light from system appearance before calling resolve).

Neutral **dark**/**light** chrome values are the exact hex from the current `DesignTokens` comments; neutral terminal is `ThemeColors.dark`/`.light`; neutral accent `#5E6AD2` (matches `DT.accentNSColor`). The five colored palettes are the verified canonical values below.

- [ ] **Step 1: Write the failing test**

Create `Tests/CoreChecks/ThemePaletteChecks.swift`:
```swift
// Tests/CoreChecks/ThemePaletteChecks.swift
import Foundation
import SimpletonCore

private func isHex6(_ s: String) -> Bool {
    guard s.hasPrefix("#") else { return false }
    let body = s.dropFirst()
    return body.count == 6 && body.allSatisfy { $0.isHexDigit }
}

private func allHexFields(_ th: AppearanceTheme) -> [String] {
    let t = th.terminal, c = th.chrome
    return [
        t.background, t.foreground, t.cursor, t.selection,
        t.black, t.red, t.green, t.yellow, t.blue, t.magenta, t.cyan, t.white,
        t.brightBlack, t.brightRed, t.brightGreen, t.brightYellow,
        t.brightBlue, t.brightMagenta, t.brightCyan, t.brightWhite,
        t.splitBorder, t.sidebar, t.tabBar,
        c.base, c.surface, c.elevated, c.hover, c.selected, c.border, c.panelBorder,
        c.textPrimary, c.textSecondary, c.textTertiary, c.textMuted, c.textFaint, c.textHelp,
        th.accent,
    ]
}

func runThemePaletteChecks(_ t: TestRunner) {
    t.suite("ThemePalette.integrity") {
        for th in ThemePalette.all {
            for hex in allHexFields(th) {
                t.expect(isHex6(hex), "\(th.id): '\(hex)' is not #RRGGBB")
            }
        }
        t.expectEqual(ThemePalette.all.count, 7, "seven presets")
        t.expect(!ThemePalette.dark.isDark == false, "dark.isDark")
        t.expect(ThemePalette.light.isDark == false, "light.isDark == false")
    }
    t.suite("ThemePalette.resolve") {
        t.expectEqual(ThemePalette.resolve("nord").id, "nord", "nord")
        t.expectEqual(ThemePalette.resolve("DRACULA").id, "dracula", "case-insensitive")
        t.expectEqual(ThemePalette.resolve("auto").id, "dark", "auto → dark (caller handles auto)")
        t.expectEqual(ThemePalette.resolve("does-not-exist").id, "dark", "unknown → dark")
    }
    t.suite("ThemePalette.neutralDrift") {
        // Dark/Light must reproduce today's exact look.
        t.expectEqual(ThemePalette.dark.chrome.base, "#0E0E11", "dark base")
        t.expectEqual(ThemePalette.dark.chrome.surface, "#131316", "dark surface")
        t.expectEqual(ThemePalette.dark.chrome.textPrimary, "#F5F6F6", "dark textPrimary")
        t.expectEqual(ThemePalette.dark.accent, "#5E6AD2", "dark accent")
        t.expectEqual(ThemePalette.dark.terminal.background, "#0B0B0E", "dark terminal bg")
        t.expectEqual(ThemePalette.light.chrome.base, "#F2F2F4", "light base")
        t.expectEqual(ThemePalette.light.chrome.textPrimary, "#1D1D1F", "light textPrimary")
        t.expectEqual(ThemePalette.light.terminal.background, "#FFFFFF", "light terminal bg")
    }
}
```
Register in `main.swift` after `runAppearanceThemeChecks(runner)`:
```swift
runThemePaletteChecks(runner)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift run CoreChecks 2>&1 | tail -20`
Expected: FAIL to compile — `cannot find 'ThemePalette' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/SimpletonCore/Models/ThemePalette.swift`. Use the exact values below (canonical, source-verified). For the colored themes, `terminal.splitBorder = chrome.border`, `terminal.sidebar = chrome.surface`, `terminal.tabBar = chrome.surface`.

```swift
// Sources/SimpletonCore/Models/ThemePalette.swift
import Foundation

/// The built-in whole-app appearance themes. Dark/Light reproduce the pre-theme look exactly;
/// the five colored themes use canonical palettes (Nord, Dracula, Gruvbox, Tokyo Night, Catppuccin).
public enum ThemePalette {

    public static let dark = AppearanceTheme(
        id: "dark", name: "Dark", isDark: true,
        terminal: ThemeColors.dark,
        chrome: ChromeColors(
            base: "#0E0E11", surface: "#131316", elevated: "#191A1E", hover: "#1D1E22",
            selected: "#232429", border: "#26262B", panelBorder: "#1E1E22",
            textPrimary: "#F5F6F6", textSecondary: "#C7CBD1", textTertiary: "#8A8F98",
            textMuted: "#62666D", textFaint: "#4A4D54", textHelp: "#6A6E76"),
        accent: "#5E6AD2")

    public static let light = AppearanceTheme(
        id: "light", name: "Light", isDark: false,
        terminal: ThemeColors.light,
        chrome: ChromeColors(
            base: "#F2F2F4", surface: "#F7F7F9", elevated: "#FFFFFF", hover: "#ECECEF",
            selected: "#E1E1E7", border: "#D6D6DC", panelBorder: "#E5E5EA",
            textPrimary: "#1D1D1F", textSecondary: "#3C3C43", textTertiary: "#6E6E76",
            textMuted: "#8A8A92", textFaint: "#AEAEB6", textHelp: "#6E6E76"),
        accent: "#5E6AD2")

    public static let tokyoNight = AppearanceTheme(
        id: "tokyo-night", name: "Tokyo Night", isDark: true,
        terminal: ThemeColors(
            background: "#1A1B26", foreground: "#C0CAF5", cursor: "#C0CAF5", selection: "#283457",
            black: "#15161E", red: "#F7768E", green: "#9ECE6A", yellow: "#E0AF68",
            blue: "#7AA2F7", magenta: "#BB9AF7", cyan: "#7DCFFF", white: "#A9B1D6",
            brightBlack: "#414868", brightRed: "#FF899D", brightGreen: "#9FE044",
            brightYellow: "#FABA4A", brightBlue: "#8DB0FF", brightMagenta: "#C7A9FF",
            brightCyan: "#A4DAFF", brightWhite: "#C0CAF5",
            splitBorder: "#3B4261", sidebar: "#1A1B26", tabBar: "#1A1B26"),
        chrome: ChromeColors(
            base: "#16161E", surface: "#1A1B26", elevated: "#292E42", hover: "#292E42",
            selected: "#283457", border: "#3B4261", panelBorder: "#292E42",
            textPrimary: "#C0CAF5", textSecondary: "#A9B1D6", textTertiary: "#545C7E",
            textMuted: "#565F89", textFaint: "#3B4261", textHelp: "#565F89"),
        accent: "#7AA2F7")

    public static let nord = AppearanceTheme(
        id: "nord", name: "Nord", isDark: true,
        terminal: ThemeColors(
            background: "#2E3440", foreground: "#D8DEE9", cursor: "#D8DEE9", selection: "#4C566A",
            black: "#3B4252", red: "#BF616A", green: "#A3BE8C", yellow: "#EBCB8B",
            blue: "#81A1C1", magenta: "#B48EAD", cyan: "#88C0D0", white: "#E5E9F0",
            brightBlack: "#4C566A", brightRed: "#BF616A", brightGreen: "#A3BE8C",
            brightYellow: "#EBCB8B", brightBlue: "#81A1C1", brightMagenta: "#B48EAD",
            brightCyan: "#8FBCBB", brightWhite: "#ECEFF4",
            splitBorder: "#4C566A", sidebar: "#3B4252", tabBar: "#3B4252"),
        chrome: ChromeColors(
            base: "#2E3440", surface: "#3B4252", elevated: "#434C5E", hover: "#434C5E",
            selected: "#4C566A", border: "#4C566A", panelBorder: "#434C5E",
            textPrimary: "#ECEFF4", textSecondary: "#E5E9F0", textTertiary: "#D8DEE9",
            textMuted: "#7B88A1", textFaint: "#4C566A", textHelp: "#D8DEE9"),
        accent: "#88C0D0")

    public static let dracula = AppearanceTheme(
        id: "dracula", name: "Dracula", isDark: true,
        terminal: ThemeColors(
            background: "#282A36", foreground: "#F8F8F2", cursor: "#F8F8F2", selection: "#44475A",
            black: "#21222C", red: "#FF5555", green: "#50FA7B", yellow: "#F1FA8C",
            blue: "#BD93F9", magenta: "#FF79C6", cyan: "#8BE9FD", white: "#F8F8F2",
            brightBlack: "#6272A4", brightRed: "#FF6E6E", brightGreen: "#69FF94",
            brightYellow: "#FFFFA5", brightBlue: "#D6ACFF", brightMagenta: "#FF92DF",
            brightCyan: "#A4FFFF", brightWhite: "#FFFFFF",
            splitBorder: "#44475A", sidebar: "#282A36", tabBar: "#282A36"),
        chrome: ChromeColors(
            base: "#21222C", surface: "#282A36", elevated: "#343746", hover: "#343746",
            selected: "#44475A", border: "#44475A", panelBorder: "#343746",
            textPrimary: "#F8F8F2", textSecondary: "#C7C9D1", textTertiary: "#8E93A8",
            textMuted: "#6272A4", textFaint: "#565A78", textHelp: "#6272A4"),
        accent: "#BD93F9")

    public static let gruvbox = AppearanceTheme(
        id: "gruvbox", name: "Gruvbox", isDark: true,
        terminal: ThemeColors(
            background: "#282828", foreground: "#EBDBB2", cursor: "#EBDBB2", selection: "#504945",
            black: "#282828", red: "#CC241D", green: "#98971A", yellow: "#D79921",
            blue: "#458588", magenta: "#B16286", cyan: "#689D6A", white: "#A89984",
            brightBlack: "#928374", brightRed: "#FB4934", brightGreen: "#B8BB26",
            brightYellow: "#FABD2F", brightBlue: "#83A598", brightMagenta: "#D3869B",
            brightCyan: "#8EC07C", brightWhite: "#EBDBB2",
            splitBorder: "#665C54", sidebar: "#282828", tabBar: "#282828"),
        chrome: ChromeColors(
            base: "#1D2021", surface: "#282828", elevated: "#3C3836", hover: "#3C3836",
            selected: "#504945", border: "#665C54", panelBorder: "#504945",
            textPrimary: "#EBDBB2", textSecondary: "#D5C4A1", textTertiary: "#BDAE93",
            textMuted: "#A89984", textFaint: "#7C6F64", textHelp: "#BDAE93"),
        accent: "#FE8019")

    public static let catppuccin = AppearanceTheme(
        id: "catppuccin", name: "Catppuccin Mocha", isDark: true,
        terminal: ThemeColors(
            background: "#1E1E2E", foreground: "#CDD6F4", cursor: "#F5E0DC", selection: "#585B70",
            black: "#45475A", red: "#F38BA8", green: "#A6E3A1", yellow: "#F9E2AF",
            blue: "#89B4FA", magenta: "#F5C2E7", cyan: "#94E2D5", white: "#BAC2DE",
            brightBlack: "#585B70", brightRed: "#F38BA8", brightGreen: "#A6E3A1",
            brightYellow: "#F9E2AF", brightBlue: "#89B4FA", brightMagenta: "#F5C2E7",
            brightCyan: "#94E2D5", brightWhite: "#A6ADC8",
            splitBorder: "#45475A", sidebar: "#181825", tabBar: "#181825"),
        chrome: ChromeColors(
            base: "#11111B", surface: "#181825", elevated: "#1E1E2E", hover: "#313244",
            selected: "#45475A", border: "#45475A", panelBorder: "#313244",
            textPrimary: "#CDD6F4", textSecondary: "#BAC2DE", textTertiary: "#A6ADC8",
            textMuted: "#7F849C", textFaint: "#6C7086", textHelp: "#9399B2"),
        accent: "#CBA6F7")

    public static let all: [AppearanceTheme] =
        [dark, light, tokyoNight, nord, dracula, gruvbox, catppuccin]

    /// Resolve a theme id to its preset (case-insensitive). Unknown ids — and `auto`, which the
    /// caller resolves against the live system appearance before calling here — fall back to `dark`.
    public static func resolve(_ id: String) -> AppearanceTheme {
        let key = id.lowercased()
        return all.first { $0.id == key } ?? dark
    }
}
```

> Note on Nord `textMuted`: the official dark ramp stops at `nord3` (#4C566A), so a legible muted grey (`#7B88A1`, a blend toward `nord4`) is used for section headers; `textFaint` stays `nord3`. Dracula's sparse ramp is filled with blends between Comment (#6272A4) and Current Line for `textTertiary`/`textFaint` so headers/footers separate visually — all within the theme's hue.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift run CoreChecks 2>&1 | tail -20`
Expected: PASS — `ThemePalette.integrity`, `.resolve`, `.neutralDrift` all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SimpletonCore/Models/ThemePalette.swift Tests/CoreChecks/ThemePaletteChecks.swift Tests/CoreChecks/main.swift
git commit -m "feat(themes): add ThemePalette with 7 presets (dark/light + 5 colored)"
```

---

### Task 3: `ThemeSettings.theme` + `AppTheme` resolution

**Files:**
- Modify: `Sources/Simpleton/Views/AppTheme.swift`

**Interfaces:**
- Consumes: `ThemePalette`, `AppearanceTheme`, `AccentPalette` (existing).
- Produces:
  - `ThemeSettings.shared.theme: AppearanceTheme` (`@Published`), plus `var themeID: String { theme.id }`.
  - `AppTheme.activeTheme: AppearanceTheme` (private-set) and updated `AppTheme.update(from:)` that resolves the theme (handling `auto`), publishes it, sets `accentNSColor` (colored theme → `theme.accent` via `NSColor(hex:)`; neutral → `AccentPalette`), and sets `NSApp.appearance`.
  - `AppTheme.isColoredThemeID(_:) -> Bool` used by the settings UI.

This task has no CoreChecks unit test (app-target, AppKit-coupled). Verify by build + the manual smoke in Step 4.

- [ ] **Step 1: Write the implementation**

In `Sources/Simpleton/Views/AppTheme.swift`, replace the `ThemeSettings` class and the `AppTheme` enum with:
```swift
final class ThemeSettings: ObservableObject {
    static let shared = ThemeSettings()
    @Published var accentID: String = "indigo"
    /// The active whole-app theme. Publishing it re-renders every chrome island that observes this.
    @Published var theme: AppearanceTheme = ThemePalette.dark
    var accent: Color { AccentPalette.color(accentID) }
    var themeID: String { theme.id }
    private init() {}
}

enum AppTheme {
    private(set) static var accentNSColor: NSColor = AccentPalette.nsColor("indigo")
    private(set) static var activeTheme: AppearanceTheme = ThemePalette.dark

    static var accent: Color { Color(nsColor: accentNSColor) }

    /// The set of colored theme ids (everything except the neutral dark/light/auto).
    static func isColoredThemeID(_ id: String) -> Bool {
        switch id.lowercased() {
        case "dark", "light", "auto": return false
        default: return true
        }
    }

    static func update(from config: AppConfig) {
        let mode = config.appearance.appearanceMode.lowercased()

        // Resolve the active theme. `auto` picks dark/light by the live system appearance.
        let resolved: AppearanceTheme
        if mode == "auto" {
            let systemLight =
                NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
            resolved = systemLight ? ThemePalette.light : ThemePalette.dark
        } else {
            resolved = ThemePalette.resolve(mode)
        }
        activeTheme = resolved
        ThemeSettings.shared.theme = resolved

        // Accent: a colored theme carries its own; neutral themes use the accent dropdown.
        if isColoredThemeID(mode) {
            accentNSColor = NSColor(hex: resolved.accent) ?? AccentPalette.nsColor("indigo")
            ThemeSettings.shared.accentID = "indigo"  // dropdown is hidden; keep a valid value
        } else {
            accentNSColor = AccentPalette.nsColor(config.appearance.accentColor)
            ThemeSettings.shared.accentID = config.appearance.accentColor
        }

        NSApp.appearance = nsAppearance(for: mode, isDark: resolved.isDark)
    }

    /// The NSAppearance for a theme id. `auto` → nil (follow system); colored/dark → darkAqua by
    /// `isDark`; light → aqua.
    static func nsAppearance(for mode: String, isDark: Bool) -> NSAppearance? {
        switch mode.lowercased() {
        case "auto": return nil
        default: return NSAppearance(named: isDark ? .darkAqua : .aqua)
        }
    }
}
```

> `NSColor(hex:)` is declared in `ThemeApplier.swift` (same module) — available here.
> The old `nsAppearance(for:)` single-arg signature is replaced; fix its two call sites in Task 8.

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | grep -E "error:|Build complete" | head`
Expected: errors at the two old `AppTheme.nsAppearance(for:)` call sites in `AppDelegate.swift` (fixed in Task 8) — that's expected; the file itself must have no errors *within* `AppTheme.swift`. If `AppTheme.swift` reports errors, fix them. (Full build goes green after Task 8.)

- [ ] **Step 3: Commit**

```bash
git add Sources/Simpleton/Views/AppTheme.swift
git commit -m "feat(themes): resolve active AppearanceTheme in AppTheme + publish on ThemeSettings"
```

---

### Task 4: `DesignTokens` reads the active theme's chrome

**Files:**
- Modify: `Sources/Simpleton/Views/DesignTokens.swift`

**Interfaces:**
- Consumes: `ThemeSettings.shared.theme.chrome` (Task 3), `Color(hex:)` (existing, `SidebarView.swift`).
- Produces: same public `DT` token API (`DT.base`, `DT.surface`, … `DT.textHelp`) — now theme-driven. `DT.accent`/`DT.accentHover`/`DT.accentNSColor` now follow `AppTheme` instead of a hardcoded indigo.

- [ ] **Step 1: Write the implementation**

In `Sources/Simpleton/Views/DesignTokens.swift`, replace the `dyn(...)` helper and every chrome/text token with reads from the active theme. Add a private helper and convert each `static let` to a `static var` computed from `ThemeSettings.shared.theme.chrome`:
```swift
    /// Resolve a chrome hex to a SwiftUI Color, falling back to magenta only if a preset is malformed
    /// (guarded against by the ThemePalette CoreChecks integrity test).
    private static func c(_ hex: String) -> Color { Color(hex: hex) ?? Color(red: 1, green: 0, blue: 1) }
    private static var chrome: ChromeColors { ThemeSettings.shared.theme.chrome }

    static var base: Color { c(chrome.base) }
    static var surface: Color { c(chrome.surface) }
    static var elevated: Color { c(chrome.elevated) }
    static var hover: Color { c(chrome.hover) }
    static var selected: Color { c(chrome.selected) }
    static var border: Color { c(chrome.border) }
    static var panelBorder: Color { c(chrome.panelBorder) }

    static var textPrimary: Color { c(chrome.textPrimary) }
    static var textSecondary: Color { c(chrome.textSecondary) }
    static var textTertiary: Color { c(chrome.textTertiary) }
    static var textMuted: Color { c(chrome.textMuted) }
    static var textFaint: Color { c(chrome.textFaint) }
    static var textHelp: Color { c(chrome.textHelp) }
```

Replace the three accent tokens so they follow the active theme (not a fixed indigo):
```swift
    static var accent: Color { AppTheme.accent }
    static var accentHover: Color { AppTheme.accent.opacity(0.82) }
    static var accentNSColor: NSColor { AppTheme.accentNSColor }
```

Delete the now-unused `dyn(...)` helper. Leave the radii/padding constants and the semantic `accentGreen/Amber/Red/Blue/Cyan`, `categoryColor`, `Banner`, `SearchBar` groups unchanged unless the compiler flags an unused `import`.

`import SimpletonCore` at the top of the file (for `ChromeColors`); add it if absent.

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | grep -E "error:|Build complete" | head`
Expected: still only the Task-8 `AppDelegate` call-site errors. `DesignTokens.swift` itself compiles. If any view referenced `DT.accentNSColor` as a stored `let` in a `#Preview` default, it still works (now a computed var).

- [ ] **Step 3: Commit**

```bash
git add Sources/Simpleton/Views/DesignTokens.swift
git commit -m "feat(themes): drive DesignTokens chrome + accent from the active theme"
```

---

### Task 5: `ThemeApplier` colors the terminal from the active theme

**Files:**
- Modify: `Sources/Simpleton/ThemeApplier.swift:14-45` (the palette-selection + caret lines)

**Interfaces:**
- Consumes: `AppTheme.activeTheme` (Task 3), `AppTheme.accentNSColor`.
- Produces: unchanged `apply(theme:config:to:)` signature (callers untouched); terminal now uses the active theme's `terminal` palette + accent.

- [ ] **Step 1: Write the implementation**

In `Sources/Simpleton/ThemeApplier.swift`, replace the `isLight`/`colors` derivation at the top of `apply(...)`:
```swift
        // Palette comes from the app's active theme (neutral dark/light or a colored theme).
        let active = AppTheme.activeTheme
        let colors = active.terminal
        let isLight = !active.isDark
```
Leave the font block unchanged. Replace the caret/selection accent source to use the theme-resolved accent:
```swift
        // Caret + selection follow the active theme's accent (matches focus border + sidebar).
        let accent = AppTheme.accentNSColor
        terminalView.caretColor = accent
        terminalView.selectedTextBackgroundColor = accent.withAlphaComponent(isLight ? 0.22 : 0.32)
```
The ANSI-palette loop and `installColors` stay as-is (they read `colors.*`). Remove the now-unused `AccentPalette.nsColor(config.appearance.accentColor)` line.

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | grep -E "error:|Build complete" | head`
Expected: only the Task-8 `AppDelegate` call-site errors remain.

- [ ] **Step 3: Commit**

```bash
git add Sources/Simpleton/ThemeApplier.swift
git commit -m "feat(themes): apply terminal palette from the active theme"
```

---

### Task 6: Chrome islands observe `ThemeSettings` (live refresh)

**Files (add one line each — the `@ObservedObject`):**
- Modify: `Sources/Simpleton/Panels/EnvironmentPanelView.swift`
- Modify: `Sources/Simpleton/Panels/ProcessesPanelView.swift`
- Modify: `Sources/Simpleton/Panels/HistoryPanelView.swift`
- Modify: `Sources/Simpleton/Panels/SSHTunnelsPanelView.swift`
- Modify: `Sources/Simpleton/Panels/NotesPanelController.swift` (the SwiftUI `NotesPanelView` struct)
- Modify: `Sources/Simpleton/Views/SidebarView.swift` (connections list — confirm it already observes; add if not)

**Interfaces:** none new — each view gains a stored `@ObservedObject var themeSettings = ThemeSettings.shared` so a `theme` change re-evaluates its `body` and re-reads `DT`.

- [ ] **Step 1: Audit which chrome views already observe**

Run:
```bash
cd /Users/bob.jansen/projects/simpleton
for f in EnvironmentPanelView ProcessesPanelView HistoryPanelView SSHTunnelsPanelView NotesPanelController; do
  printf "%-24s " "$f"; grep -c "ThemeSettings.shared" Sources/Simpleton/Panels/$f.swift 2>/dev/null || echo 0
done
```
Expected: prints `0` for the views that do NOT yet observe. Only those need editing.

- [ ] **Step 2: Add the observer to each view that printed 0**

In each such SwiftUI `View` struct that uses `DT.*`, add as the first stored property inside the struct:
```swift
    @ObservedObject private var themeSettings = ThemeSettings.shared
```
(The property only needs to exist to establish observation; it does not need to be referenced in `body`.)

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | grep -E "error:|warning: .*never used|Build complete" | head`
Expected: no errors. A "never used" warning on `themeSettings` is acceptable, but prefer silencing it by using the accent somewhere it already applies, or name it `_themeSettings` only if the codebase does elsewhere (it does not — keep `themeSettings`).

- [ ] **Step 4: Commit**

```bash
git add Sources/Simpleton/Panels Sources/Simpleton/Views/SidebarView.swift
git commit -m "feat(themes): observe ThemeSettings in remaining chrome panels for live theme switching"
```

---

### Task 7: Unified theme picker in the Appearance tab

**Files:**
- Modify: `Sources/Simpleton/Views/PreferencesWindow.swift:266-294` (the `AppearanceTab` Theme section)

**Interfaces:**
- Consumes: `ThemePalette.all` (Task 2), `AppTheme.isColoredThemeID` (Task 3), `AccentPalette` (existing). Binding `$config.appearance.appearanceMode` now carries theme ids; `onChanged(config)` unchanged.

- [ ] **Step 1: Write the implementation**

Replace the `Picker("Appearance", …)` and `Picker("Accent color", …)` block inside `AppearanceTab`'s Theme `Section` with a unified theme picker + conditional accent:
```swift
                Picker("Theme", selection: $config.appearance.appearanceMode) {
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                    Text("Auto").tag("auto")
                    Divider()
                    ForEach(ThemePalette.all.filter { $0.id != "dark" && $0.id != "light" }) { th in
                        Text(th.name).tag(th.id)
                    }
                }
                .onChange(of: config.appearance.appearanceMode) { onChanged(config) }

                if !AppTheme.isColoredThemeID(config.appearance.appearanceMode) {
                    Picker("Accent color", selection: $config.appearance.accentColor) {
                        ForEach(AccentPalette.options, id: \.id) { opt in
                            (Text(Image(systemName: "circle.fill")).foregroundColor(AccentPalette.color(opt.id))
                                + Text("  " + opt.label))
                                .tag(opt.id)
                        }
                    }
                    .onChange(of: config.appearance.accentColor) { onChanged(config) }
                    Text("Focus ring, selection, and cursor use this color. “Match System” follows your macOS accent.")
                        .font(.system(size: 11))
                        .foregroundColor(DT.textHelp)
                } else {
                    Text("This theme sets its own accent color.")
                        .font(.system(size: 11))
                        .foregroundColor(DT.textHelp)
                }
```
The `Auto` case still resolves live via `AppTheme.update`. `ThemePalette.all` order already puts the five colored themes after Divider.

- [ ] **Step 2: Build + manual smoke**

Run: `swift build 2>&1 | grep -E "error:|Build complete" | head` — expect only Task-8 errors until Task 8 lands; after Task 8, build clean, then:
```bash
scripts/e2e/make-app-bundle.sh debug && open .build/Simpleton.app
```
Open Settings → Appearance: the **Theme** dropdown lists Dark/Light/Auto then the five colored themes; selecting a colored theme hides the accent dropdown and shows the "sets its own accent" note.

- [ ] **Step 3: Commit**

```bash
git add Sources/Simpleton/Views/PreferencesWindow.swift
git commit -m "feat(themes): unified theme picker with conditional accent in Appearance settings"
```

---

### Task 8: Wire live switching in AppDelegate (build-green)

**Files:**
- Modify: `Sources/Simpleton/AppDelegate.swift` — the `theme` computed prop (14-22), the two `AppTheme.nsAppearance(for:)` call sites, `systemAppearanceChanged` (already fine).

**Interfaces:**
- Consumes: `AppTheme.update` / `AppTheme.activeTheme` / `AppTheme.nsAppearance(for:isDark:)` (Task 3).
- Produces: full build green; theme changes recolor terminal + chrome + window live via the existing `applyConfigToAllPanes()`.

- [ ] **Step 1: Fix the `theme` computed property**

The legacy `Theme(name:colors:)` value is now derived from the active `AppearanceTheme`. Replace `AppDelegate`'s `theme` computed property (lines 14-22) with:
```swift
    private var theme: Theme {
        Theme(name: AppTheme.activeTheme.name, colors: AppTheme.activeTheme.terminal)
    }
```
(`ThemeApplier` ignores this value now, but `applyThemeToAllPanes(_:)` and session code still pass it.)

- [ ] **Step 2: Fix the two `nsAppearance(for:)` call sites**

In `applyConfigToAllPanes()` (the per-window loop) replace:
```swift
                window.appearance = AppTheme.nsAppearance(for: config.appearance.appearanceMode)
```
with:
```swift
                window.appearance = AppTheme.nsAppearance(
                    for: config.appearance.appearanceMode, isDark: AppTheme.activeTheme.isDark)
```
`applyConfigToAllPanes()` already calls `AppTheme.update(from: config)` first (line 636), so `AppTheme.activeTheme` is current. Grep for any other `nsAppearance(for:` call and apply the same two-arg fix:
```bash
grep -rn "nsAppearance(for:" Sources/Simpleton
```

- [ ] **Step 3: Build + run checks**

Run:
```bash
swift build 2>&1 | grep -E "error:|Build complete" | head
swift run CoreChecks 2>&1 | tail -5
```
Expected: `Build complete!` and `✓ CoreChecks: all N checks passed`.

- [ ] **Step 4: Manual smoke — the whole feature**

```bash
scripts/e2e/make-app-bundle.sh debug && open .build/Simpleton.app
```
Verify:
- Launch default (Dark) looks **identical** to before (neutral drift check).
- Settings → Appearance → pick **Dracula**: terminal, sidebar, panels, tab bar, borders, and accent all recolor **live** (no relaunch); accent dropdown hides.
- Switch **Dracula → Nord → Tokyo Night**: chrome + terminal update each time (colored→colored, same `darkAqua`).
- Pick **Light**: white terminal + light chrome; accent dropdown returns.
- Pick **Auto**, flip macOS System Settings dark/light: app follows.
- Open a new tab / split while a colored theme is active: new panes use the theme (not black).

- [ ] **Step 5: Commit**

```bash
git add Sources/Simpleton/AppDelegate.swift
git commit -m "feat(themes): wire live theme switching through applyConfigToAllPanes"
```

---

## Self-review notes

- **Spec coverage:** theme set (Task 2), whole-app depth (Tasks 4/5/6), unified picker + conditional accent (Task 7), live switching (Tasks 3/4/6/8), neutral-drift fidelity (Task 2 test + Task 8 smoke), migration-free config (`appearanceMode` gains ids; no code), CoreChecks tests (Tasks 1/2). All covered.
- **Type consistency:** `AppearanceTheme`/`ChromeColors`/`ThemePalette.resolve`/`AppTheme.activeTheme`/`AppTheme.isColoredThemeID`/`nsAppearance(for:isDark:)` are used with identical signatures across tasks.
- **Known deferrals (not blockers):** Gruvbox/Catppuccin `selection` and the Nord/Dracula lower text tiers used the source-verified defaults with alternatives noted in the palette research; adjust hex in `ThemePalette.swift` if you prefer an alternate official shade — no structural change.
</content>
