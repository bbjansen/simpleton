// Tests/SimpletonCoreTests/Models/SmartGroupTests.swift
import XCTest

@testable import SimpletonCore

final class SmartGroupTests: XCTestCase {

    func testSmartGroupRoundTrip() throws {
        let group = SmartGroup(
            id: UUID(),
            name: "Production",
            color: "#ef4444",
            combinator: .or,
            rules: [
                SmartGroupRule(field: .hostname, operator: .contains, value: "prod"),
                SmartGroupRule(field: .tag, operator: .equals, value: "production"),
            ]
        )

        let data = try JSONEncoder().encode(group)
        let decoded = try JSONDecoder().decode(SmartGroup.self, from: data)

        XCTAssertEqual(decoded.name, "Production")
        XCTAssertEqual(decoded.color, "#ef4444")
        XCTAssertEqual(decoded.combinator, .or)
        XCTAssertEqual(decoded.rules.count, 2)
        XCTAssertEqual(decoded.rules[0].field, .hostname)
        XCTAssertEqual(decoded.rules[0].operator, .contains)
        XCTAssertEqual(decoded.rules[0].value, "prod")
    }

    func testSmartGroupFileRoundTrip() throws {
        let file = SmartGroupFile(groups: [
            SmartGroup(
                name: "Staging", color: "#eab308", combinator: .and,
                rules: [
                    SmartGroupRule(field: .hostname, operator: .contains, value: "staging")
                ])
        ])
        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(SmartGroupFile.self, from: data)
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.groups.count, 1)
    }

    func testSmartGroupMatchesBookmark_OR() {
        let group = SmartGroup(
            name: "Test",
            color: "#000",
            combinator: .or,
            rules: [
                SmartGroupRule(field: .hostname, operator: .contains, value: "prod"),
                SmartGroupRule(field: .tag, operator: .equals, value: "staging"),
            ]
        )
        let bookmark = Bookmark(name: "server", host: "api-prod-01")
        XCTAssertTrue(group.matches(bookmark))

        let bookmark2 = Bookmark(name: "server", host: "api-dev-01", tags: ["staging"])
        XCTAssertTrue(group.matches(bookmark2))

        let bookmark3 = Bookmark(name: "server", host: "api-dev-01")
        XCTAssertFalse(group.matches(bookmark3))
    }

    func testSmartGroupMatchesBookmark_AND() {
        let group = SmartGroup(
            name: "Test",
            color: "#000",
            combinator: .and,
            rules: [
                SmartGroupRule(field: .hostname, operator: .contains, value: "prod"),
                SmartGroupRule(field: .tag, operator: .equals, value: "web"),
            ]
        )
        let match = Bookmark(name: "s", host: "web-prod-01", tags: ["web"])
        XCTAssertTrue(group.matches(match))

        let noMatch = Bookmark(name: "s", host: "web-prod-01", tags: ["db"])
        XCTAssertFalse(group.matches(noMatch))
    }

    func testRuleOperators() {
        let bookmark = Bookmark(name: "web-prod", host: "10.0.1.5", user: "deploy", tags: ["prod"])

        XCTAssertTrue(SmartGroupRule(field: .hostname, operator: .equals, value: "10.0.1.5").matches(bookmark))
        XCTAssertTrue(SmartGroupRule(field: .hostname, operator: .startsWith, value: "10.0").matches(bookmark))
        XCTAssertTrue(SmartGroupRule(field: .hostname, operator: .endsWith, value: ".1.5").matches(bookmark))
        XCTAssertTrue(SmartGroupRule(field: .hostname, operator: .contains, value: "0.1").matches(bookmark))
        XCTAssertTrue(SmartGroupRule(field: .name, operator: .contains, value: "prod").matches(bookmark))
        XCTAssertTrue(SmartGroupRule(field: .user, operator: .equals, value: "deploy").matches(bookmark))
        XCTAssertTrue(SmartGroupRule(field: .tag, operator: .equals, value: "prod").matches(bookmark))
        XCTAssertFalse(SmartGroupRule(field: .tag, operator: .equals, value: "staging").matches(bookmark))
    }
}
