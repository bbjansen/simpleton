// Tests/CoreChecks/TestRunner.swift
//
// Minimal no-Xcode test harness. XCTest and the swift-testing `Testing` module are
// both unavailable on this machine (Command Line Tools only, no Xcode.app), so checks
// run as a plain executable. This collects pass/fail counts and exits non-zero on any
// failure, so it works in CI or a pre-commit hook via `swift run CoreChecks`.
import Foundation

final class TestRunner {
    private(set) var passed = 0
    private(set) var failed = 0
    private var failures: [String] = []
    private var suiteName = "?"

    /// Group related checks under a named suite.
    func suite(_ name: String, _ body: () -> Void) {
        suiteName = name
        body()
    }

    /// Record a boolean expectation.
    func expect(_ condition: Bool, _ message: @autoclosure () -> String, line: Int = #line) {
        if condition {
            passed += 1
        } else {
            failed += 1
            failures.append("[\(suiteName)] \(message())  (line \(line))")
        }
    }

    /// Record an equality expectation with a helpful diff message.
    func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String = "", line: Int = #line) {
        expect(actual == expected,
               "\(label.isEmpty ? "" : label + ": ")expected \(expected), got \(actual)",
               line: line)
    }

    /// Print a summary and return a process exit code (0 = all passed).
    func finish() -> Int32 {
        print("")
        if failures.isEmpty {
            print("✓ CoreChecks: all \(passed) checks passed")
            return 0
        }
        print("✗ CoreChecks: \(failed) failed, \(passed) passed")
        for f in failures { print("  ✗ \(f)") }
        return 1
    }
}
