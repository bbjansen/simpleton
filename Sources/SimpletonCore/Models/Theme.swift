// Sources/SimpletonCore/Models/Theme.swift
import Foundation

public struct ThemeColors: Codable, Equatable {
    public var background: String
    public var foreground: String
    public var cursor: String
    public var selection: String
    public var black: String
    public var red: String
    public var green: String
    public var yellow: String
    public var blue: String
    public var magenta: String
    public var cyan: String
    public var white: String
    public var brightBlack: String
    public var brightRed: String
    public var brightGreen: String
    public var brightYellow: String
    public var brightBlue: String
    public var brightMagenta: String
    public var brightCyan: String
    public var brightWhite: String
    public var splitBorder: String
    public var sidebar: String
    public var tabBar: String

    public init(
        background: String = "#1a1a2e", foreground: String = "#e2e8f0",
        cursor: String = "#818cf8", selection: String = "#334155",
        black: String = "#1a1a2e", red: String = "#ef4444",
        green: String = "#22c55e", yellow: String = "#eab308",
        blue: String = "#3b82f6", magenta: String = "#a855f7",
        cyan: String = "#06b6d4", white: String = "#e2e8f0",
        brightBlack: String = "#475569", brightRed: String = "#fca5a5",
        brightGreen: String = "#86efac", brightYellow: String = "#fde68a",
        brightBlue: String = "#93c5fd", brightMagenta: String = "#d8b4fe",
        brightCyan: String = "#67e8f9", brightWhite: String = "#f8fafc",
        splitBorder: String = "#333333", sidebar: String = "#0f0f1a",
        tabBar: String = "#16162a"
    ) {
        self.background = background; self.foreground = foreground
        self.cursor = cursor; self.selection = selection
        self.black = black; self.red = red; self.green = green; self.yellow = yellow
        self.blue = blue; self.magenta = magenta; self.cyan = cyan; self.white = white
        self.brightBlack = brightBlack; self.brightRed = brightRed
        self.brightGreen = brightGreen; self.brightYellow = brightYellow
        self.brightBlue = brightBlue; self.brightMagenta = brightMagenta
        self.brightCyan = brightCyan; self.brightWhite = brightWhite
        self.splitBorder = splitBorder; self.sidebar = sidebar; self.tabBar = tabBar
    }
}

public struct Theme: Codable, Equatable {
    public var name: String
    public var colors: ThemeColors

    public init(name: String, colors: ThemeColors = ThemeColors()) {
        self.name = name
        self.colors = colors
    }
}

public struct ThemeFile: Codable {
    public let version: Int
    public var theme: Theme

    private enum CodingKeys: String, CodingKey {
        case version, name, colors
    }

    public init(version: Int = 1, theme: Theme) {
        self.version = version
        self.theme = theme
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        let name = try container.decode(String.self, forKey: .name)
        let colors = try container.decode(ThemeColors.self, forKey: .colors)
        theme = Theme(name: name, colors: colors)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(theme.name, forKey: .name)
        try container.encode(theme.colors, forKey: .colors)
    }
}
