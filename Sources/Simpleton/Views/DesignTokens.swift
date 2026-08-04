import AppKit
// Sources/Simpleton/Views/DesignTokens.swift
import SwiftUI

/// Centralized design tokens for the Simpleton premium dark theme.
enum DT {

    // MARK: - Base Colors (dynamic — adapt to Light / Dark / Auto appearance)

    /// A color that resolves to `light` or `dark` based on the view's macOS appearance, so the
    /// whole SwiftUI chrome follows Dark / Light / Auto without per-view branching.
    private static func dyn(
        _ lr: Double, _ lg: Double, _ lb: Double, _ dr: Double, _ dg: Double, _ db: Double
    ) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return isDark
                    ? NSColor(srgbRed: dr, green: dg, blue: db, alpha: 1)
                    : NSColor(srgbRed: lr, green: lg, blue: lb, alpha: 1)
            })
    }

    /// Deep neutral base background — window/chrome. Dark #0E0E11 / Light #F2F2F4
    static let base = dyn(0.949, 0.949, 0.957, 0.055, 0.055, 0.067)
    /// Chrome surface — sidebar / tab bar. Dark #131316 / Light #F7F7F9
    static let surface = dyn(0.969, 0.969, 0.976, 0.075, 0.075, 0.086)
    /// Elevated surface — popovers / cards. Dark #191A1E / Light #FFFFFF
    static let elevated = dyn(1.0, 1.0, 1.0, 0.098, 0.102, 0.118)
    /// Hover fill. Dark #1D1E22 / Light #ECECEF
    static let hover = dyn(0.925, 0.925, 0.937, 0.114, 0.118, 0.133)
    /// Selected-row fill — one step past hover. Dark #232429 / Light #E1E1E7
    static let selected = dyn(0.882, 0.882, 0.906, 0.137, 0.141, 0.161)
    /// Thin hairline border. Dark #26262B / Light #D6D6DC
    static let border = dyn(0.839, 0.839, 0.863, 0.149, 0.149, 0.169)
    /// Subtle border for panels. Dark #1E1E22 / Light #E5E5EA
    static let panelBorder = dyn(0.898, 0.898, 0.918, 0.118, 0.118, 0.133)

    // MARK: - Text Colors

    /// Primary text — off-white on dark, near-black on light. Dark #F5F6F6 / Light #1D1D1F
    static let textPrimary = dyn(0.114, 0.114, 0.122, 0.961, 0.965, 0.965)
    /// Secondary text. Dark #C7CBD1 / Light #3C3C43
    static let textSecondary = dyn(0.235, 0.235, 0.263, 0.780, 0.796, 0.820)
    /// Tertiary text / captions. Dark #8A8F98 / Light #6E6E76
    static let textTertiary = dyn(0.431, 0.431, 0.463, 0.541, 0.561, 0.596)
    /// Muted text / section headers. Dark #62666D / Light #8A8A92
    static let textMuted = dyn(0.541, 0.541, 0.573, 0.384, 0.400, 0.427)
    /// Very muted text / footers. Dark #4A4D54 / Light #AEAEB6
    static let textFaint = dyn(0.682, 0.682, 0.714, 0.290, 0.302, 0.329)
    /// Help text in preferences. Dark #6A6E76 / Light #6E6E76
    static let textHelp = dyn(0.431, 0.431, 0.463, 0.416, 0.431, 0.463)

    // MARK: - Accent (single signature — focus, selection, cursor)

    /// The one signature accent: Linear indigo (#5E6AD2). Used ONLY for focus rings,
    /// selection, and the cursor — everything else stays grayscale or semantic.
    static let accent = Color(red: 0.369, green: 0.416, blue: 0.824)
    /// Brighter accent for hover / pressed states (#828FFF).
    static let accentHover = Color(red: 0.510, green: 0.561, blue: 1.000)
    /// AppKit variant of the signature accent (layer borders, carets).
    static let accentNSColor = NSColor(red: 0.369, green: 0.416, blue: 0.824, alpha: 1)

    // MARK: - Semantic status + legacy accents

    static let accentIndigo = accent
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
}
