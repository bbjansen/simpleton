// Tests/CoreChecks/SmartGroupChecks.swift
// Ported from Tests/SimpletonCoreTests/Models/SmartGroupTests.swift
import Foundation
import SimpletonCore

func runSmartGroupChecks(_ t: TestRunner) {
    t.suite("SmartGroup.testSmartGroupRoundTrip") {
        do {
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

            t.expectEqual(decoded.name, "Production", "name")
            t.expectEqual(decoded.color, "#ef4444", "color")
            t.expectEqual(decoded.combinator, .or, "combinator")
            t.expectEqual(decoded.rules.count, 2, "rules count")
            t.expectEqual(decoded.rules.first?.field, .hostname, "first rule field")
            t.expectEqual(decoded.rules.first?.operator, .contains, "first rule operator")
            t.expectEqual(decoded.rules.first?.value, "prod", "first rule value")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    t.suite("SmartGroup.testSmartGroupFileRoundTrip") {
        do {
            let file = SmartGroupFile(groups: [
                SmartGroup(
                    name: "Staging", color: "#eab308", combinator: .and,
                    rules: [
                        SmartGroupRule(field: .hostname, operator: .contains, value: "staging")
                    ])
            ])
            let data = try JSONEncoder().encode(file)
            let decoded = try JSONDecoder().decode(SmartGroupFile.self, from: data)
            t.expectEqual(decoded.version, 1, "version")
            t.expectEqual(decoded.groups.count, 1, "groups count")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    t.suite("SmartGroup.testSmartGroupMatchesBookmark_OR") {
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
        t.expect(group.matches(bookmark), "matches on hostname contains prod")

        let bookmark2 = Bookmark(name: "server", host: "api-dev-01", tags: ["staging"])
        t.expect(group.matches(bookmark2), "matches on tag staging")

        let bookmark3 = Bookmark(name: "server", host: "api-dev-01")
        t.expect(!group.matches(bookmark3), "no rule matches")
    }

    t.suite("SmartGroup.testSmartGroupMatchesBookmark_AND") {
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
        t.expect(group.matches(match), "both rules match")

        let noMatch = Bookmark(name: "s", host: "web-prod-01", tags: ["db"])
        t.expect(!group.matches(noMatch), "tag rule fails -> no match")
    }

    t.suite("SmartGroup.testRuleOperators") {
        let bookmark = Bookmark(name: "web-prod", host: "10.0.1.5", user: "deploy", tags: ["prod"])
        t.expect(
            SmartGroupRule(field: .hostname, operator: .equals, value: "10.0.1.5").matches(bookmark), "hostname equals")
        t.expect(
            SmartGroupRule(field: .hostname, operator: .startsWith, value: "10.0").matches(bookmark),
            "hostname startsWith")
        t.expect(
            SmartGroupRule(field: .hostname, operator: .endsWith, value: ".1.5").matches(bookmark), "hostname endsWith")
        t.expect(
            SmartGroupRule(field: .hostname, operator: .contains, value: "0.1").matches(bookmark), "hostname contains")
        t.expect(SmartGroupRule(field: .name, operator: .contains, value: "prod").matches(bookmark), "name contains")
        t.expect(SmartGroupRule(field: .user, operator: .equals, value: "deploy").matches(bookmark), "user equals")
        t.expect(SmartGroupRule(field: .tag, operator: .equals, value: "prod").matches(bookmark), "tag equals")
        t.expect(
            !SmartGroupRule(field: .tag, operator: .equals, value: "staging").matches(bookmark), "tag not matching")
    }
}
