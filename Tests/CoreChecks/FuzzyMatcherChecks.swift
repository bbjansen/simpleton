// Tests/CoreChecks/FuzzyMatcherChecks.swift
// Ported from Tests/SimpletonCoreTests/Core/FuzzyMatcherTests.swift
import SimpletonCore

func runFuzzyMatcherChecks(_ t: TestRunner) {
    t.suite("FuzzyMatcher.testExactMatch") {
        let result = FuzzyMatcher.score(query: "prod", candidate: "prod")
        t.expect(result != nil, "exact match returns a score")
        t.expect((result ?? 0) > 0, "exact match score > 0")
    }

    t.suite("FuzzyMatcher.testPrefixMatch") {
        let result = FuzzyMatcher.score(query: "web", candidate: "web-prod-01")
        t.expect(result != nil, "prefix match returns a score")
    }

    t.suite("FuzzyMatcher.testSubsequenceMatch") {
        let result = FuzzyMatcher.score(query: "wp", candidate: "web-prod-01")
        t.expect(result != nil, "subsequence match returns a score")
    }

    t.suite("FuzzyMatcher.testNoMatch") {
        let result = FuzzyMatcher.score(query: "xyz", candidate: "web-prod-01")
        t.expect(result == nil, "no match returns nil")
    }

    t.suite("FuzzyMatcher.testCaseInsensitive") {
        let result = FuzzyMatcher.score(query: "WEB", candidate: "web-prod-01")
        t.expect(result != nil, "case-insensitive match returns a score")
    }

    t.suite("FuzzyMatcher.testRanking") {
        let exact = FuzzyMatcher.score(query: "api", candidate: "api")!
        let prefix = FuzzyMatcher.score(query: "api", candidate: "api-server")!
        let substring = FuzzyMatcher.score(query: "api", candidate: "my-api-server")!
        t.expect(exact >= prefix, "exact >= prefix")
        t.expect(prefix >= substring, "prefix >= substring")
    }

    t.suite("FuzzyMatcher.testEmptyQuery") {
        let result = FuzzyMatcher.score(query: "", candidate: "anything")
        t.expect(result != nil, "empty query matches everything")
    }
}
