// Tests/CoreChecks/main.swift
//
// Entry point for the no-Xcode check runner. Register new suites here.
// Run with:  swift run CoreChecks
import Foundation

let runner = TestRunner()

// Core (synchronous)
runCommandClassifierChecks(runner)
runAIModelListChecks(runner)
runShellIntegrationChecks(runner)
runTerminalURIChecks(runner)
runAtomicFileWriterChecks(runner)
runFieldValidatorChecks(runner)
runFrecencyScorerChecks(runner)
runFuzzyMatcherChecks(runner)
runSSHConfigParserChecks(runner)

// Core (async — actor-backed stores)
await runBookmarkStoreChecks(runner)
await runConfigStoreChecks(runner)
await runConnectionStoreChecks(runner)

// Models (synchronous)
runAppConfigChecks(runner)
runWorkspaceChecks(runner)
runConnectionChecks(runner)
runBookmarkChecks(runner)
runFrecencyEntryChecks(runner)
runSessionStateChecks(runner)
runSmartGroupChecks(runner)
runSplitNodeChecks(runner)
runThemeChecks(runner)
runAppearanceThemeChecks(runner)
runThemePaletteChecks(runner)

exit(runner.finish())
