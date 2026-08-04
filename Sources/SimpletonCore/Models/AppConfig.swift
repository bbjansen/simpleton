// Sources/SimpletonCore/Models/AppConfig.swift
import Foundation

public enum ShellDetection: String, Codable {
    case environment
    case dscl
}

public enum WorkingDirectoryMode: String, Codable {
    case home
    case custom
}

public enum CursorStyle: String, Codable {
    case block
    case beam
    case underline
}

public enum BellBehavior: String, Codable {
    case visual
    case audio
    case none
}

public enum UpdateCheckMode: String, Codable {
    case automatic
    case manual
    case disabled
}

public struct GeneralConfig: Codable, Equatable {
    public var shell: String
    public var shellDetection: ShellDetection
    public var workingDirectory: WorkingDirectoryMode
    public var customWorkingDirectory: String?
    public var restorePreviousSession: Bool
    public var confirmBeforeClosing: Bool
    public var checkForUpdates: UpdateCheckMode
    public var termVariable: String
    /// Opt-in: inject OSC 133 shell integration (currently zsh) for exit-status feedback.
    public var shellIntegration: Bool

    public init(
        shell: String = "$SHELL",
        shellDetection: ShellDetection = .environment,
        workingDirectory: WorkingDirectoryMode = .home,
        customWorkingDirectory: String? = nil,
        restorePreviousSession: Bool = true,
        confirmBeforeClosing: Bool = true,
        checkForUpdates: UpdateCheckMode = .automatic,
        termVariable: String = "xterm-256color",
        shellIntegration: Bool = false
    ) {
        self.shell = shell
        self.shellDetection = shellDetection
        self.workingDirectory = workingDirectory
        self.customWorkingDirectory = customWorkingDirectory
        self.restorePreviousSession = restorePreviousSession
        self.confirmBeforeClosing = confirmBeforeClosing
        self.checkForUpdates = checkForUpdates
        self.termVariable = termVariable
        self.shellIntegration = shellIntegration
    }

    /// Tolerant decoding: any key missing from an older config.json falls back to its default,
    /// so adding fields (like shellIntegration) never drops a user's existing settings.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GeneralConfig()
        shell = try c.decodeIfPresent(String.self, forKey: .shell) ?? d.shell
        shellDetection = try c.decodeIfPresent(ShellDetection.self, forKey: .shellDetection) ?? d.shellDetection
        workingDirectory =
            try c.decodeIfPresent(WorkingDirectoryMode.self, forKey: .workingDirectory) ?? d.workingDirectory
        customWorkingDirectory = try c.decodeIfPresent(String.self, forKey: .customWorkingDirectory)
        restorePreviousSession =
            try c.decodeIfPresent(Bool.self, forKey: .restorePreviousSession) ?? d.restorePreviousSession
        confirmBeforeClosing = try c.decodeIfPresent(Bool.self, forKey: .confirmBeforeClosing) ?? d.confirmBeforeClosing
        checkForUpdates = try c.decodeIfPresent(UpdateCheckMode.self, forKey: .checkForUpdates) ?? d.checkForUpdates
        termVariable = try c.decodeIfPresent(String.self, forKey: .termVariable) ?? d.termVariable
        shellIntegration = try c.decodeIfPresent(Bool.self, forKey: .shellIntegration) ?? d.shellIntegration
    }
}

public struct AppearanceConfig: Codable, Equatable {
    public var theme: String
    public var fontFamily: String
    public var fontSize: Int
    public var cursorStyle: CursorStyle
    public var cursorBlink: Bool
    public var windowOpacity: Double
    public var thinStrokes: Bool

    public init(
        theme: String = "default-dark",
        fontFamily: String = "SF Mono",
        fontSize: Int = 13,
        cursorStyle: CursorStyle = .block,
        cursorBlink: Bool = true,
        windowOpacity: Double = 1.0,
        thinStrokes: Bool = false
    ) {
        self.theme = theme
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.cursorStyle = cursorStyle
        self.cursorBlink = cursorBlink
        self.windowOpacity = windowOpacity
        self.thinStrokes = thinStrokes
    }
}

public struct TerminalConfig: Codable, Equatable {
    public var scrollbackLines: Int
    public var copyOnSelect: Bool
    public var pasteOnRightClick: Bool
    public var bellBehavior: BellBehavior
    public var mouseReporting: Bool
    public var closeOnCleanExit: Bool

    public init(
        scrollbackLines: Int = 10000,
        copyOnSelect: Bool = false,
        pasteOnRightClick: Bool = true,
        bellBehavior: BellBehavior = .visual,
        mouseReporting: Bool = true,
        closeOnCleanExit: Bool = false
    ) {
        self.scrollbackLines = scrollbackLines
        self.copyOnSelect = copyOnSelect
        self.pasteOnRightClick = pasteOnRightClick
        self.bellBehavior = bellBehavior
        self.mouseReporting = mouseReporting
        self.closeOnCleanExit = closeOnCleanExit
    }
}

public struct SSHConfig: Codable, Equatable {
    public var defaultUser: String?
    public var keepaliveInterval: Int
    public var autoReconnect: Bool
    public var maxReconnectAttempts: Int
    public var agentForwarding: Bool
    public var x11Forwarding: Bool
    public var controlMaster: Bool

    public init(
        defaultUser: String? = nil,
        keepaliveInterval: Int = 60,
        autoReconnect: Bool = true,
        maxReconnectAttempts: Int = 10,
        agentForwarding: Bool = false,
        x11Forwarding: Bool = false,
        controlMaster: Bool = false
    ) {
        self.defaultUser = defaultUser
        self.keepaliveInterval = keepaliveInterval
        self.autoReconnect = autoReconnect
        self.maxReconnectAttempts = maxReconnectAttempts
        self.agentForwarding = agentForwarding
        self.x11Forwarding = x11Forwarding
        self.controlMaster = controlMaster
    }
}

public struct AppConfig: Codable, Equatable {
    public var general: GeneralConfig
    public var appearance: AppearanceConfig
    public var terminal: TerminalConfig
    public var ssh: SSHConfig

    public init(
        general: GeneralConfig = GeneralConfig(),
        appearance: AppearanceConfig = AppearanceConfig(),
        terminal: TerminalConfig = TerminalConfig(),
        ssh: SSHConfig = SSHConfig()
    ) {
        self.general = general
        self.appearance = appearance
        self.terminal = terminal
        self.ssh = ssh
    }
}

public struct ConfigFile: Codable {
    public let version: Int
    public var config: AppConfig

    private enum CodingKeys: String, CodingKey {
        case version, general, appearance, terminal, ssh
    }

    public init(version: Int = 1, config: AppConfig = AppConfig()) {
        self.version = version
        self.config = config
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        let general = try container.decode(GeneralConfig.self, forKey: .general)
        let appearance = try container.decode(AppearanceConfig.self, forKey: .appearance)
        let terminal = try container.decode(TerminalConfig.self, forKey: .terminal)
        let ssh = try container.decode(SSHConfig.self, forKey: .ssh)
        config = AppConfig(general: general, appearance: appearance, terminal: terminal, ssh: ssh)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(config.general, forKey: .general)
        try container.encode(config.appearance, forKey: .appearance)
        try container.encode(config.terminal, forKey: .terminal)
        try container.encode(config.ssh, forKey: .ssh)
    }
}
