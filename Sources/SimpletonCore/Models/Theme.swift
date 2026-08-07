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
        background: String = "#0B0B0E", foreground: String = "#EDEDED",
        cursor: String = "#5E6AD2", selection: String = "#2A3350",
        black: String = "#15151A", red: String = "#ef4444",
        green: String = "#22c55e", yellow: String = "#eab308",
        blue: String = "#3b82f6", magenta: String = "#a855f7",
        cyan: String = "#06b6d4", white: String = "#e2e8f0",
        brightBlack: String = "#475569", brightRed: String = "#fca5a5",
        brightGreen: String = "#86efac", brightYellow: String = "#fde68a",
        brightBlue: String = "#93c5fd", brightMagenta: String = "#d8b4fe",
        brightCyan: String = "#67e8f9", brightWhite: String = "#f8fafc",
        splitBorder: String = "#26262B", sidebar: String = "#131316",
        tabBar: String = "#131316"
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

extension ThemeColors {
    /// Premium neutral-dark terminal palette (the default).
    public static let dark = ThemeColors()

    /// macOS-native light terminal palette — Terminal "Basic"-style ANSI, tuned to stay readable
    /// on a white background. The caret/selection are overridden at apply time by the accent.
    public static let light = ThemeColors(
        background: "#FFFFFF", foreground: "#1D1D1F",
        cursor: "#5E6AD2", selection: "#B4D5FF",
        black: "#000000", red: "#990000",
        green: "#00A600", yellow: "#7A6300",
        blue: "#0000B2", magenta: "#B200B2",
        cyan: "#00A6B2", white: "#BFBFBF",
        brightBlack: "#5A5A5A", brightRed: "#E50000",
        brightGreen: "#00A600", brightYellow: "#8A8A00",
        brightBlue: "#0000FF", brightMagenta: "#E500E5",
        brightCyan: "#00A6B2", brightWhite: "#E5E5E5",
        splitBorder: "#D6D6DC", sidebar: "#F7F7F9",
        tabBar: "#F2F2F4"
    )
}

/// UI-chrome colors for a whole-app theme — the tokens `DesignTokens` renders (sidebar, panels,
/// borders, text tiers). Stored as `#RRGGBB` hex, mirroring `ThemeColors`.
public struct ChromeColors: Codable, Equatable {
    public var base: String
    public var surface: String
    public var elevated: String
    public var hover: String
    public var selected: String
    public var border: String
    public var panelBorder: String
    public var textPrimary: String
    public var textSecondary: String
    public var textTertiary: String
    public var textMuted: String
    public var textFaint: String
    public var textHelp: String

    public init(
        base: String, surface: String, elevated: String, hover: String, selected: String,
        border: String, panelBorder: String, textPrimary: String, textSecondary: String,
        textTertiary: String, textMuted: String, textFaint: String, textHelp: String
    ) {
        self.base = base; self.surface = surface; self.elevated = elevated
        self.hover = hover; self.selected = selected; self.border = border
        self.panelBorder = panelBorder; self.textPrimary = textPrimary
        self.textSecondary = textSecondary; self.textTertiary = textTertiary
        self.textMuted = textMuted; self.textFaint = textFaint; self.textHelp = textHelp
    }
}

/// A whole-app appearance theme: terminal palette + UI chrome + accent, all in one value.
public struct AppearanceTheme: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let isDark: Bool
    public var terminal: ThemeColors
    public var chrome: ChromeColors
    public var accent: String  // #RRGGBB
    /// Optional chrome gradient stops (#RRGGBB, top→bottom). When set, the sidebar/header/panels
    /// wash with this blend instead of the flat `chrome.surface`. Nil for solid themes.
    public var gradient: [String]?

    public init(
        id: String, name: String, isDark: Bool,
        terminal: ThemeColors, chrome: ChromeColors, accent: String,
        gradient: [String]? = nil
    ) {
        self.id = id; self.name = name; self.isDark = isDark
        self.terminal = terminal; self.chrome = chrome; self.accent = accent
        self.gradient = gradient
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
