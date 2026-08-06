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
