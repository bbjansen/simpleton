// Tests/SimpletonCoreTests/Models/AppConfigTests.swift
import XCTest
@testable import SimpletonCore

final class AppConfigTests: XCTestCase {

    func testDefaultConfig() {
        let config = AppConfig()
        XCTAssertEqual(config.general.shell, "$SHELL")
        XCTAssertEqual(config.general.shellDetection, .environment)
        XCTAssertEqual(config.general.workingDirectory, .home)
        XCTAssertEqual(config.general.restorePreviousSession, true)
        XCTAssertEqual(config.general.confirmBeforeClosing, true)
        XCTAssertEqual(config.general.termVariable, "xterm-256color")
        XCTAssertEqual(config.appearance.fontFamily, "SF Mono")
        XCTAssertEqual(config.appearance.fontSize, 13)
        XCTAssertEqual(config.appearance.cursorStyle, .block)
        XCTAssertEqual(config.terminal.scrollbackLines, 10000)
        XCTAssertEqual(config.terminal.closeOnCleanExit, false)
        XCTAssertEqual(config.ssh.keepaliveInterval, 60)
        XCTAssertEqual(config.ssh.autoReconnect, true)
        XCTAssertEqual(config.ssh.maxReconnectAttempts, 10)
    }

    func testConfigRoundTrip() throws {
        var config = AppConfig()
        config.appearance.fontSize = 16
        config.terminal.scrollbackLines = 50000
        config.ssh.defaultUser = "admin"

        let file = ConfigFile(config: config)
        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(ConfigFile.self, from: data)

        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.config.appearance.fontSize, 16)
        XCTAssertEqual(decoded.config.terminal.scrollbackLines, 50000)
        XCTAssertEqual(decoded.config.ssh.defaultUser, "admin")
    }

    func testConfigMergesDefaults() throws {
        // Simulate a config file with missing keys (older version)
        let json = """
        {"version":1,"general":{"shell":"$SHELL","shellDetection":"environment","workingDirectory":"home","restorePreviousSession":true,"confirmBeforeClosing":true,"checkForUpdates":"automatic","termVariable":"xterm-256color","customWorkingDirectory":null},"appearance":{"theme":"default-dark","fontFamily":"SF Mono","fontSize":15,"cursorStyle":"beam","cursorBlink":true,"windowOpacity":1.0,"thinStrokes":false},"terminal":{"scrollbackLines":10000,"copyOnSelect":false,"pasteOnRightClick":true,"bellBehavior":"visual","mouseReporting":true,"closeOnCleanExit":false},"ssh":{"defaultUser":null,"keepaliveInterval":60,"autoReconnect":true,"maxReconnectAttempts":10,"agentForwarding":false,"x11Forwarding":false,"controlMaster":false}}
        """
        let decoded = try JSONDecoder().decode(ConfigFile.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.config.appearance.fontSize, 15)
        XCTAssertEqual(decoded.config.appearance.cursorStyle, .beam)
    }
}
