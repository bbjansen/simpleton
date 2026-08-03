// Tests/CoreChecks/AppConfigChecks.swift
// Ported from Tests/SimpletonCoreTests/Models/AppConfigTests.swift
import Foundation
import SimpletonCore

func runAppConfigChecks(_ t: TestRunner) {
    t.suite("AppConfig.testDefaultConfig") {
        let config = AppConfig()
        t.expectEqual(config.general.shell, "$SHELL", "shell")
        t.expectEqual(config.general.shellDetection, .environment, "shellDetection")
        t.expectEqual(config.general.workingDirectory, .home, "workingDirectory")
        t.expectEqual(config.general.restorePreviousSession, true, "restorePreviousSession")
        t.expectEqual(config.general.confirmBeforeClosing, true, "confirmBeforeClosing")
        t.expectEqual(config.general.termVariable, "xterm-256color", "termVariable")
        t.expectEqual(config.appearance.fontFamily, "SF Mono", "fontFamily")
        t.expectEqual(config.appearance.fontSize, 13, "fontSize")
        t.expectEqual(config.appearance.cursorStyle, .block, "cursorStyle")
        t.expectEqual(config.terminal.scrollbackLines, 10000, "scrollbackLines")
        t.expectEqual(config.terminal.closeOnCleanExit, false, "closeOnCleanExit")
        t.expectEqual(config.ssh.keepaliveInterval, 60, "keepaliveInterval")
        t.expectEqual(config.ssh.autoReconnect, true, "autoReconnect")
        t.expectEqual(config.ssh.maxReconnectAttempts, 10, "maxReconnectAttempts")
    }

    t.suite("AppConfig.testConfigRoundTrip") {
        do {
            var config = AppConfig()
            config.appearance.fontSize = 16
            config.terminal.scrollbackLines = 50000
            config.ssh.defaultUser = "admin"

            let file = ConfigFile(config: config)
            let data = try JSONEncoder().encode(file)
            let decoded = try JSONDecoder().decode(ConfigFile.self, from: data)

            t.expectEqual(decoded.version, 1, "version")
            t.expectEqual(decoded.config.appearance.fontSize, 16, "fontSize")
            t.expectEqual(decoded.config.terminal.scrollbackLines, 50000, "scrollbackLines")
            t.expectEqual(decoded.config.ssh.defaultUser, "admin", "defaultUser")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }

    t.suite("AppConfig.testConfigMergesDefaults") {
        do {
            // Simulate a config file with a full key set (older version)
            let json = """
            {"version":1,"general":{"shell":"$SHELL","shellDetection":"environment","workingDirectory":"home","restorePreviousSession":true,"confirmBeforeClosing":true,"checkForUpdates":"automatic","termVariable":"xterm-256color","customWorkingDirectory":null},"appearance":{"theme":"default-dark","fontFamily":"SF Mono","fontSize":15,"cursorStyle":"beam","cursorBlink":true,"windowOpacity":1.0,"thinStrokes":false},"terminal":{"scrollbackLines":10000,"copyOnSelect":false,"pasteOnRightClick":true,"bellBehavior":"visual","mouseReporting":true,"closeOnCleanExit":false},"ssh":{"defaultUser":null,"keepaliveInterval":60,"autoReconnect":true,"maxReconnectAttempts":10,"agentForwarding":false,"x11Forwarding":false,"controlMaster":false}}
            """
            let decoded = try JSONDecoder().decode(ConfigFile.self, from: Data(json.utf8))
            t.expectEqual(decoded.config.appearance.fontSize, 15, "fontSize from file")
            t.expectEqual(decoded.config.appearance.cursorStyle, .beam, "cursorStyle from file")
        } catch {
            t.expect(false, "unexpected error: \(error)")
        }
    }
}
