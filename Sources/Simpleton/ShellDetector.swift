// Sources/Simpleton/ShellDetector.swift
import Foundation
import SimpletonCore

enum ShellDetector {

    /// Resolves the user's default shell based on the config's detection strategy.
    /// Falls back to /bin/zsh if detection fails.
    static func detectShell(config: AppConfig) -> String {
        let shellSetting = config.general.shell

        // If the user set an explicit path, use it
        if shellSetting != "$SHELL" && shellSetting.hasPrefix("/") {
            if FileManager.default.isExecutableFile(atPath: shellSetting) {
                return shellSetting
            }
        }

        switch config.general.shellDetection {
        case .environment:
            return shellFromEnvironment() ?? shellFromDscl() ?? "/bin/zsh"
        case .dscl:
            return shellFromDscl() ?? shellFromEnvironment() ?? "/bin/zsh"
        }
    }

    /// Resolve the user's working directory based on config.
    static func workingDirectory(config: AppConfig) -> String {
        switch config.general.workingDirectory {
        case .home:
            return NSHomeDirectory()
        case .custom:
            if let custom = config.general.customWorkingDirectory,
                FileManager.default.fileExists(atPath: custom)
            {
                return custom
            }
            return NSHomeDirectory()
        }
    }

    private static func shellFromEnvironment() -> String? {
        guard let shell = ProcessInfo.processInfo.environment["SHELL"],
            !shell.isEmpty,
            FileManager.default.isExecutableFile(atPath: shell)
        else {
            return nil
        }
        return shell
    }

    private static func shellFromDscl() -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        process.arguments = [".", "-read", "/Users/\(NSUserName())", "UserShell"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        // Output format: "UserShell: /bin/zsh"
        let parts = output.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let shell = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard FileManager.default.isExecutableFile(atPath: shell) else { return nil }
        return shell
    }
}
