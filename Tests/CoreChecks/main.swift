// Tests/CoreChecks/main.swift
//
// Entry point for the no-Xcode check runner. Register new suites here.
// Run with:  swift run CoreChecks
import Foundation

let runner = TestRunner()

runCommandClassifierChecks(runner)

exit(runner.finish())
