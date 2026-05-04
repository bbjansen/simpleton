// Tests/SimpletonCoreTests/Core/FuzzyMatcherTests.swift
import XCTest
@testable import SimpletonCore

final class FuzzyMatcherTests: XCTestCase {

    func testExactMatch() {
        let result = FuzzyMatcher.score(query: "prod", candidate: "prod")
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!, 0)
    }

    func testPrefixMatch() {
        let result = FuzzyMatcher.score(query: "web", candidate: "web-prod-01")
        XCTAssertNotNil(result)
    }

    func testSubsequenceMatch() {
        let result = FuzzyMatcher.score(query: "wp", candidate: "web-prod-01")
        XCTAssertNotNil(result)
    }

    func testNoMatch() {
        let result = FuzzyMatcher.score(query: "xyz", candidate: "web-prod-01")
        XCTAssertNil(result)
    }

    func testCaseInsensitive() {
        let result = FuzzyMatcher.score(query: "WEB", candidate: "web-prod-01")
        XCTAssertNotNil(result)
    }

    func testRanking() {
        let exact = FuzzyMatcher.score(query: "api", candidate: "api")!
        let prefix = FuzzyMatcher.score(query: "api", candidate: "api-server")!
        let substring = FuzzyMatcher.score(query: "api", candidate: "my-api-server")!
        XCTAssertGreaterThanOrEqual(exact, prefix)
        XCTAssertGreaterThanOrEqual(prefix, substring)
    }

    func testEmptyQuery() {
        let result = FuzzyMatcher.score(query: "", candidate: "anything")
        XCTAssertNotNil(result) // empty query matches everything
    }
}
