// Tests/CoreChecks/ThemeChecks.swift
// Ported from Tests/SimpletonCoreTests/Models/ThemeTests.swift
import Foundation
import SimpletonCore

func runThemeChecks(_ t: TestRunner) {
    t.suite("Theme.testThemeRoundTrip") {
        do {
            let theme = Theme(name: "Test Dark", colors: ThemeColors())
            let file = ThemeFile(theme: theme)
            let data = try JSONEncoder().encode(file)
            let decoded = try JSONDecoder().decode(ThemeFile.self, from: data)
            t.expectEqual(decoded.version, 1, "version")
            t.expectEqual(decoded.theme.name, "Test Dark", "theme name")
            t.expectEqual(decoded.theme.colors.background, "#1a1a2e", "background color")
            t.expectEqual(decoded.theme.colors.red, "#ef4444", "red color")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }
}
