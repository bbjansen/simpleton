import AppKit
// Sources/Simpleton/Views/DesignTokens.swift
import SwiftUI

/// Centralized design tokens for the Simpleton premium dark theme.
enum DT {

    // MARK: - Base Colors

    /// Deep dark base background (#0D0D14)
    static let base = Color(red: 0.051, green: 0.051, blue: 0.078)
    /// Slightly lighter surface (#111118)
    static let surface = Color(red: 0.067, green: 0.067, blue: 0.094)
    /// Elevated surface (#15151F)
    static let elevated = Color(red: 0.082, green: 0.082, blue: 0.122)
    /// Hover / active fill (#1A1A2E)
    static let hover = Color(red: 0.102, green: 0.102, blue: 0.180)
    /// Thin border color (#2A2A3A)
    static let border = Color(red: 0.165, green: 0.165, blue: 0.227)
    /// Subtle border for panels (#1A1A2A)
    static let panelBorder = Color(red: 0.102, green: 0.102, blue: 0.165)

    // MARK: - Text Colors

    /// Primary text (bright white)
    static let textPrimary = Color.white
    /// Secondary text
    static let textSecondary = Color.white.opacity(0.7)
    /// Tertiary text / captions
    static let textTertiary = Color(red: 0.353, green: 0.353, blue: 0.416)  // #5A5A6A
    /// Muted text / section headers
    static let textMuted = Color(red: 0.290, green: 0.290, blue: 0.353)  // #4A4A5A
    /// Very muted text / footers
    static let textFaint = Color(red: 0.227, green: 0.227, blue: 0.290)  // #3A3A4A
    /// Help text in preferences
    static let textHelp = Color(red: 0.416, green: 0.416, blue: 0.478)  // #6A6A7A

    // MARK: - Accent Colors (muted, pop against dark)

    static let accentIndigo = Color(red: 0.380, green: 0.400, blue: 0.950)
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

    // MARK: - Animation

    static let hoverAnimation = Animation.easeInOut(duration: 0.2)

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
