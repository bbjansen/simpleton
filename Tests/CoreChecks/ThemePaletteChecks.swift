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
