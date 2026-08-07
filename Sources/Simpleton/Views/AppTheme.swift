// Sources/Simpleton/Views/AppTheme.swift
import AppKit
import SimpletonCore
import SwiftUI

/// Resolves the macOS-integrated accent options offered in Settings. The signature default is
/// "indigo"; "system" tracks the live macOS accent (System Settings → Appearance); the rest are
/// the eight named macOS accent colors, using their dark-appearance (brightened) values so they
/// read cleanly on the dark chrome.
enum AccentPalette {

    /// Dropdown order + labels. `id` is what persists to `AppConfig.appearance.accentColor`.
    static let options: [(id: String, label: String)] = [
        ("indigo", "Indigo"),
        ("system", "Match System"),
        ("blue", "Blue"),
        ("purple", "Purple"),
        ("pink", "Pink"),
        ("red", "Red"),
        ("orange", "Orange"),
        ("yellow", "Yellow"),
        ("green", "Green"),
        ("graphite", "Graphite"),
    ]

    static func nsColor(_ id: String) -> NSColor {
        switch id.lowercased() {
        case "system": return .controlAccentColor
        case "blue": return NSColor(srgbRed: 0.039, green: 0.518, blue: 1.0, alpha: 1)  // #0A84FF
        case "purple": return NSColor(srgbRed: 0.749, green: 0.353, blue: 0.949, alpha: 1)  // #BF5AF2
        case "pink": return NSColor(srgbRed: 1.0, green: 0.392, blue: 0.509, alpha: 1)  // #FF6482
        case "red": return NSColor(srgbRed: 1.0, green: 0.271, blue: 0.227, alpha: 1)  // #FF453A
        case "orange": return NSColor(srgbRed: 1.0, green: 0.624, blue: 0.039, alpha: 1)  // #FF9F0A
        case "yellow": return NSColor(srgbRed: 1.0, green: 0.839, blue: 0.039, alpha: 1)  // #FFD60A
        case "green": return NSColor(srgbRed: 0.188, green: 0.820, blue: 0.345, alpha: 1)  // #30D158
        case "graphite": return NSColor(srgbRed: 0.557, green: 0.557, blue: 0.576, alpha: 1)  // #8E8E93
        case "indigo": return NSColor(srgbRed: 0.369, green: 0.416, blue: 0.824, alpha: 1)  // #5E6AD2
        default: return NSColor(srgbRed: 0.369, green: 0.416, blue: 0.824, alpha: 1)  // indigo
        }
    }

    static func color(_ id: String) -> Color { Color(nsColor: nsColor(id)) }

    static func label(_ id: String) -> String {
        options.first { $0.id == id.lowercased() }?.label ?? "Indigo"
    }
}

/// Observable accent for SwiftUI. Publishing the id makes every `.tint(themeSettings.accent)` and
/// accent-colored control refresh live the moment the user changes the accent in Settings — a plain
/// static wouldn't, so accents would only appear after a relaunch.
final class ThemeSettings: ObservableObject {
    static let shared = ThemeSettings()
    @Published var accentID: String = "indigo"
    /// The active whole-app theme. Publishing it re-renders every chrome island that observes this.
    @Published var theme: AppearanceTheme = ThemePalette.dark
    /// Opacity of the theme-color wash in `themedGlass` (1 = solid, lower = more see-through frost).
    /// Driven by `AppConfig.appearance.chromeTranslucency`; published so chrome re-frosts live.
    @Published var chromeOpacity: Double = 0.94
    /// The configured monospaced font family — the same font the terminal uses. Published so the
    /// code-adjacent text in panels/sidebar (file paths, hashes, PIDs, command snippets, via
    /// `DT.monoFont`) re-renders to match the terminal the instant the font is changed in Settings.
    @Published var monoFontFamily: String = "SF Mono"
    /// The resolved accent — a colored theme's own accent, or the chosen accent for neutral themes.
    /// Reads `AppTheme.accentNSColor` (set by `AppTheme.update` before `theme` is published) rather
    /// than `accentID`, so colored themes tint chrome with their signature accent, not indigo.
    var accent: Color { Color(nsColor: AppTheme.accentNSColor) }
    var themeID: String { theme.id }
    private init() {}
}

/// Runtime-resolved appearance: one source of truth for the active accent, read by both AppKit
/// (focus border, caret) and SwiftUI (`.tint`). AppDelegate calls `update(from:)` on launch and
/// whenever Settings change so every surface stays consistent.
enum AppTheme {
    private(set) static var accentNSColor: NSColor = AccentPalette.nsColor("indigo")
    private(set) static var activeTheme: AppearanceTheme = ThemePalette.dark

    /// SwiftUI accent — recomputed from the live NSColor each access so views pick up changes on
    /// their next body evaluation.
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
        let translucency = min(max(config.appearance.chromeTranslucency, 0), 0.6)
        ThemeSettings.shared.chromeOpacity = 0.94 - translucency
        ThemeSettings.shared.monoFontFamily = config.appearance.fontFamily
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
