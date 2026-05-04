// Tests/SimpletonCoreTests/Models/ThemeTests.swift
import XCTest
@testable import SimpletonCore

final class ThemeTests: XCTestCase {

    func testThemeRoundTrip() throws {
        let theme = Theme(name: "Test Dark", colors: ThemeColors())
        let file = ThemeFile(theme: theme)
        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(ThemeFile.self, from: data)
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.theme.name, "Test Dark")
        XCTAssertEqual(decoded.theme.colors.background, "#1a1a2e")
        XCTAssertEqual(decoded.theme.colors.red, "#ef4444")
    }
}
