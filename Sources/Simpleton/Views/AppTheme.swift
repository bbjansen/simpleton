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
    var accent: Color { AccentPalette.color(accentID) }
    private init() {}
}

/// Runtime-resolved appearance: one source of truth for the active accent, read by both AppKit
/// (focus border, caret) and SwiftUI (`.tint`). AppDelegate calls `update(from:)` on launch and
/// whenever Settings change so every surface stays consistent.
enum AppTheme {
    private(set) static var accentNSColor: NSColor = AccentPalette.nsColor("indigo")

    /// SwiftUI accent — recomputed from the live NSColor each access so views pick up changes on
    /// their next body evaluation.
    static var accent: Color { Color(nsColor: accentNSColor) }

    static func update(from config: AppConfig) {
        accentNSColor = AccentPalette.nsColor(config.appearance.accentColor)
        // Drive the observable so open SwiftUI surfaces (settings, sidebar) re-tint immediately.
        ThemeSettings.shared.accentID = config.appearance.accentColor
        // Set the appearance app-wide so EVERY window follows the mode — the terminal windows and
        // the Settings / panel windows alike (nil = follow the system, for Auto).
        NSApp.appearance = nsAppearance(for: config.appearance.appearanceMode)
    }

    /// The NSAppearance for an appearance-mode string. `nil` means "follow the system" (Auto).
    static func nsAppearance(for mode: String) -> NSAppearance? {
        switch mode.lowercased() {
        case "light": return NSAppearance(named: .aqua)
        case "auto": return nil
        default: return NSAppearance(named: .darkAqua)
        }
    }
}
