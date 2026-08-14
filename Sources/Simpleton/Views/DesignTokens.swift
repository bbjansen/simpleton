import AppKit
// Sources/Simpleton/Views/DesignTokens.swift
import SimpletonCore
import SwiftUI

/// Centralized design tokens for the Simpleton premium dark theme.
enum DT {

    // MARK: - Base Colors (theme-driven)

    /// Resolve a chrome hex to a SwiftUI Color, falling back to magenta only if a preset is malformed
    /// (guarded against by the ThemePalette CoreChecks integrity test).
    private static func c(_ hex: String) -> Color { Color(hex: hex) ?? Color(red: 1, green: 0, blue: 1) }
    private static var chrome: ChromeColors { ThemeSettings.shared.theme.chrome }

    /// Deep neutral base background — window/chrome.
    static var base: Color { c(chrome.base) }
    /// Chrome surface — sidebar / tab bar.
    static var surface: Color { c(chrome.surface) }
    /// Elevated surface — popovers / cards.
    static var elevated: Color { c(chrome.elevated) }
    /// Hover fill.
    static var hover: Color { c(chrome.hover) }
    /// Selected-row fill — one step past hover.
    static var selected: Color { c(chrome.selected) }
    /// Thin hairline border.
    static var border: Color { c(chrome.border) }
    /// Subtle border for panels.
    static var panelBorder: Color { c(chrome.panelBorder) }

    // MARK: - Text Colors

    /// Primary text — off-white on dark, near-black on light.
    static var textPrimary: Color { c(chrome.textPrimary) }
    /// Secondary text.
    static var textSecondary: Color { c(chrome.textSecondary) }
    /// Tertiary text / captions.
    static var textTertiary: Color { c(chrome.textTertiary) }
    /// Muted text / section headers.
    static var textMuted: Color { c(chrome.textMuted) }
    /// Very muted text / footers.
    static var textFaint: Color { c(chrome.textFaint) }
    /// Help text in preferences.
    static var textHelp: Color { c(chrome.textHelp) }

    // MARK: - Accent (single signature — focus, selection, cursor)

    /// The active theme's accent color. Used ONLY for focus rings, selection, and the cursor —
    /// everything else stays grayscale or semantic.
    static var accent: Color { AppTheme.accent }
    /// Accent with reduced opacity for hover / pressed states.
    static var accentHover: Color { AppTheme.accent.opacity(0.82) }
    /// AppKit variant of the signature accent (layer borders, carets).
    static var accentNSColor: NSColor { AppTheme.accentNSColor }

    // MARK: - Semantic status + legacy accents

    static var accentIndigo: Color { accent }
    static let accentGreen = Color(red: 0.300, green: 0.800, blue: 0.500)
    static let accentAmber = Color(red: 0.950, green: 0.700, blue: 0.200)
    static let accentRed = Color(red: 0.950, green: 0.350, blue: 0.350)
    static let accentBlue = Color(red: 0.450, green: 0.650, blue: 1.000)
    static let accentCyan = Color(red: 0.300, green: 0.800, blue: 0.850)

    // MARK: - Category Colors (for command palette)

    static func categoryColor(for category: String) -> Color {
        switch category.lowercased() {
        case "window": return Color(red: 0.145, green: 0.388, blue: 0.922)  // #2563EB
        case "ssh": return Color(red: 0.086, green: 0.639, blue: 0.290)  // #16A34A
        case "view": return Color(red: 0.576, green: 0.200, blue: 0.918)  // #9333EA
        case "edit": return Color(red: 0.918, green: 0.345, blue: 0.047)  // #EA580C
        case "file": return accentCyan
        case "help": return accentAmber
        default: return textTertiary
        }
    }

    // MARK: - Fonts

    /// The configured terminal font, for the code-adjacent monospaced text in panels/sidebar (file
    /// paths, git hashes, PIDs, env values, command snippets) so it matches the terminal instead of
    /// the system mono. Reads the published family from `ThemeSettings`, so callers that observe it
    /// re-render live when the font is changed in Settings. Falls back to the system monospaced font
    /// when the configured family can't be resolved (bad name / empty), preserving the mono look.
    static func monoFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let family = ThemeSettings.shared.monoFontFamily
        if !family.isEmpty, NSFont(name: family, size: size) != nil {
            return .custom(family, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - Radii

    static let radiusCard: CGFloat = 8
    static let radiusButton: CGFloat = 6
    static let radiusPanel: CGFloat = 12
    static let radiusBanner: CGFloat = 10
    static let radiusPill: CGFloat = 10

    // MARK: - Terminal

    /// Breathing room between the terminal content and its pane edge (Warp/Ghostty do ~2–16).
    static let terminalPadding: CGFloat = 12

    // MARK: - Animation

    /// Native-feeling hover/press motion. `.snappy` is the macOS spring (quick, tight, no
    /// overshoot) and respects Reduce Motion automatically.
    static let hoverAnimation = Animation.snappy(duration: 0.18)

    // MARK: - Banner NSColors (for AppKit PaneController)

    enum Banner {
        static let successTint = NSColor(red: 0.30, green: 0.80, blue: 0.50, alpha: 1)
        static let successBg = NSColor(red: 0.06, green: 0.08, blue: 0.07, alpha: 0.92)
        static let successBorder = NSColor(red: 0.30, green: 0.80, blue: 0.50, alpha: 0.20)

        static let errorTint = NSColor(red: 0.95, green: 0.35, blue: 0.35, alpha: 1)
        static let errorBg = NSColor(red: 0.12, green: 0.06, blue: 0.07, alpha: 0.92)
        static let errorBorder = NSColor(red: 0.95, green: 0.35, blue: 0.35, alpha: 0.20)

        static let warningTint = NSColor(red: 0.95, green: 0.70, blue: 0.20, alpha: 1)
        static let warningBg = NSColor(red: 0.10, green: 0.08, blue: 0.05, alpha: 0.92)
        static let warningBorder = NSColor(red: 0.95, green: 0.70, blue: 0.20, alpha: 0.18)

        static let infoTint = NSColor(red: 0.45, green: 0.65, blue: 1.00, alpha: 1)
        static let infoBg = NSColor(red: 0.06, green: 0.07, blue: 0.12, alpha: 0.92)
        static let infoBorder = NSColor(red: 0.45, green: 0.65, blue: 1.00, alpha: 0.18)

        static let cornerRadius: CGFloat = 10
        static let borderWidth: CGFloat = 0.5
        static let height: CGFloat = 36
        static let inset: CGFloat = 8
        static let iconSize: CGFloat = 14
    }

    // MARK: - Search Bar NSColors

    enum SearchBar {
        static let background = NSColor(red: 0.051, green: 0.051, blue: 0.078, alpha: 0.92)
        static let borderColor = NSColor(red: 0.165, green: 0.165, blue: 0.227, alpha: 1)
    }

    // MARK: - Results grid (AppKit NSTableView)

    /// Themed NSColors for the SQL results grid. They read the same chrome hex
    /// as the SwiftUI tokens (via NSColor(hex:) in ThemeApplier), so the grid
    /// re-themes live when the appearance changes.
    enum Grid {
        private static func ns(_ hex: String) -> NSColor {
            NSColor(hex: hex) ?? NSColor(red: 1, green: 0, blue: 1, alpha: 1)
        }
        private static var chrome: ChromeColors { ThemeSettings.shared.theme.chrome }

        /// The grid's base surface — used to make the frozen pinned pane opaque so the main table's
        /// columns don't bleed through it during horizontal scroll.
        static var base: NSColor { ns(chrome.base) }
        static var headerBackground: NSColor { ns(chrome.surface) }
        static var headerText: NSColor { ns(chrome.textSecondary) }
        static var gridline: NSColor { ns(chrome.border).withAlphaComponent(0.5) }
        static var rowText: NSColor { ns(chrome.textPrimary) }
        static var rowTextSecondary: NSColor { ns(chrome.textSecondary) }
        static var nullText: NSColor { ns(chrome.textFaint) }
        static var selectionFill: NSColor { ns(chrome.selected) }

        /// Tint for a staged (uncommitted) cell edit — amber, matching `DT.accentAmber`. Callers
        /// apply their own alpha.
        static let stagedTint = NSColor(red: 0.950, green: 0.700, blue: 0.200, alpha: 1)
        /// Flash for an edit that failed to parse for the column's type — red, matching `DT.accentRed`.
        static let invalidTint = NSColor(red: 0.950, green: 0.350, blue: 0.350, alpha: 1)

        /// Distinct hues for categorical (enum) cell pills; a value maps to a
        /// stable slot via `SQLGridData.enumColorIndex`.
        static let enumPalette: [NSColor] = [
            "#ef4444", "#f59e0b", "#10b981", "#3b82f6", "#8b5cf6", "#ec4899", "#14b8a6", "#9ca3af",
        ].compactMap { NSColor(hex: $0) }
    }

    /// The configured mono font as an NSFont (tabular digits; matches the
    /// terminal). Falls back to the system monospaced font.
    static func monoNSFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let family = ThemeSettings.shared.monoFontFamily
        if !family.isEmpty, let f = NSFont(name: family, size: size) { return f }
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
}
