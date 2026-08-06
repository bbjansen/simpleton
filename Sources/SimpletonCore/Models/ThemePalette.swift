// Sources/SimpletonCore/Models/ThemePalette.swift
import Foundation

/// The built-in whole-app appearance themes. Dark/Light reproduce the pre-theme look exactly;
/// the five colored themes use canonical palettes (Nord, Dracula, Gruvbox, Tokyo Night, Catppuccin).
public enum ThemePalette {

    public static let dark = AppearanceTheme(
        id: "dark", name: "Dark", isDark: true,
        terminal: ThemeColors.dark,
        chrome: ChromeColors(
            base: "#0E0E11", surface: "#131316", elevated: "#191A1E", hover: "#1D1E22",
            selected: "#232429", border: "#26262B", panelBorder: "#1E1E22",
            textPrimary: "#F5F6F6", textSecondary: "#C7CBD1", textTertiary: "#8A8F98",
            textMuted: "#62666D", textFaint: "#4A4D54", textHelp: "#6A6E76"),
        accent: "#5E6AD2")

    public static let light = AppearanceTheme(
        id: "light", name: "Light", isDark: false,
        terminal: ThemeColors.light,
        chrome: ChromeColors(
            base: "#F2F2F4", surface: "#F7F7F9", elevated: "#FFFFFF", hover: "#ECECEF",
            selected: "#E1E1E7", border: "#D6D6DC", panelBorder: "#E5E5EA",
            textPrimary: "#1D1D1F", textSecondary: "#3C3C43", textTertiary: "#6E6E76",
            textMuted: "#8A8A92", textFaint: "#AEAEB6", textHelp: "#6E6E76"),
        accent: "#5E6AD2")

    public static let tokyoNight = AppearanceTheme(
        id: "tokyo-night", name: "Tokyo Night", isDark: true,
        terminal: ThemeColors(
            background: "#1A1B26", foreground: "#C0CAF5", cursor: "#C0CAF5", selection: "#283457",
            black: "#15161E", red: "#F7768E", green: "#9ECE6A", yellow: "#E0AF68",
            blue: "#7AA2F7", magenta: "#BB9AF7", cyan: "#7DCFFF", white: "#A9B1D6",
            brightBlack: "#414868", brightRed: "#FF899D", brightGreen: "#9FE044",
            brightYellow: "#FABA4A", brightBlue: "#8DB0FF", brightMagenta: "#C7A9FF",
            brightCyan: "#A4DAFF", brightWhite: "#C0CAF5",
            splitBorder: "#3B4261", sidebar: "#1A1B26", tabBar: "#1A1B26"),
        chrome: ChromeColors(
            base: "#16161E", surface: "#1A1B26", elevated: "#292E42", hover: "#292E42",
            selected: "#283457", border: "#3B4261", panelBorder: "#292E42",
            textPrimary: "#C0CAF5", textSecondary: "#A9B1D6", textTertiary: "#545C7E",
            textMuted: "#565F89", textFaint: "#3B4261", textHelp: "#565F89"),
        accent: "#7AA2F7")

    public static let nord = AppearanceTheme(
        id: "nord", name: "Nord", isDark: true,
        terminal: ThemeColors(
            background: "#2E3440", foreground: "#D8DEE9", cursor: "#D8DEE9", selection: "#4C566A",
            black: "#3B4252", red: "#BF616A", green: "#A3BE8C", yellow: "#EBCB8B",
            blue: "#81A1C1", magenta: "#B48EAD", cyan: "#88C0D0", white: "#E5E9F0",
            brightBlack: "#4C566A", brightRed: "#BF616A", brightGreen: "#A3BE8C",
            brightYellow: "#EBCB8B", brightBlue: "#81A1C1", brightMagenta: "#B48EAD",
            brightCyan: "#8FBCBB", brightWhite: "#ECEFF4",
            splitBorder: "#4C566A", sidebar: "#3B4252", tabBar: "#3B4252"),
        chrome: ChromeColors(
            base: "#2E3440", surface: "#3B4252", elevated: "#434C5E", hover: "#434C5E",
            selected: "#4C566A", border: "#4C566A", panelBorder: "#434C5E",
            textPrimary: "#ECEFF4", textSecondary: "#E5E9F0", textTertiary: "#D8DEE9",
            textMuted: "#7B88A1", textFaint: "#4C566A", textHelp: "#D8DEE9"),
        accent: "#88C0D0")

    public static let dracula = AppearanceTheme(
        id: "dracula", name: "Dracula", isDark: true,
        terminal: ThemeColors(
            background: "#282A36", foreground: "#F8F8F2", cursor: "#F8F8F2", selection: "#44475A",
            black: "#21222C", red: "#FF5555", green: "#50FA7B", yellow: "#F1FA8C",
            blue: "#BD93F9", magenta: "#FF79C6", cyan: "#8BE9FD", white: "#F8F8F2",
            brightBlack: "#6272A4", brightRed: "#FF6E6E", brightGreen: "#69FF94",
            brightYellow: "#FFFFA5", brightBlue: "#D6ACFF", brightMagenta: "#FF92DF",
            brightCyan: "#A4FFFF", brightWhite: "#FFFFFF",
            splitBorder: "#44475A", sidebar: "#282A36", tabBar: "#282A36"),
        chrome: ChromeColors(
            base: "#21222C", surface: "#282A36", elevated: "#343746", hover: "#343746",
            selected: "#44475A", border: "#44475A", panelBorder: "#343746",
            textPrimary: "#F8F8F2", textSecondary: "#C7C9D1", textTertiary: "#8E93A8",
            textMuted: "#6272A4", textFaint: "#565A78", textHelp: "#6272A4"),
        accent: "#BD93F9")

    public static let gruvbox = AppearanceTheme(
        id: "gruvbox", name: "Gruvbox", isDark: true,
        terminal: ThemeColors(
            background: "#282828", foreground: "#EBDBB2", cursor: "#EBDBB2", selection: "#504945",
            black: "#282828", red: "#CC241D", green: "#98971A", yellow: "#D79921",
            blue: "#458588", magenta: "#B16286", cyan: "#689D6A", white: "#A89984",
            brightBlack: "#928374", brightRed: "#FB4934", brightGreen: "#B8BB26",
            brightYellow: "#FABD2F", brightBlue: "#83A598", brightMagenta: "#D3869B",
            brightCyan: "#8EC07C", brightWhite: "#EBDBB2",
            splitBorder: "#665C54", sidebar: "#282828", tabBar: "#282828"),
        chrome: ChromeColors(
            base: "#1D2021", surface: "#282828", elevated: "#3C3836", hover: "#3C3836",
            selected: "#504945", border: "#665C54", panelBorder: "#504945",
            textPrimary: "#EBDBB2", textSecondary: "#D5C4A1", textTertiary: "#BDAE93",
            textMuted: "#A89984", textFaint: "#7C6F64", textHelp: "#BDAE93"),
        accent: "#FE8019")

    public static let catppuccin = AppearanceTheme(
        id: "catppuccin", name: "Catppuccin Mocha", isDark: true,
        terminal: ThemeColors(
            background: "#1E1E2E", foreground: "#CDD6F4", cursor: "#F5E0DC", selection: "#585B70",
            black: "#45475A", red: "#F38BA8", green: "#A6E3A1", yellow: "#F9E2AF",
            blue: "#89B4FA", magenta: "#F5C2E7", cyan: "#94E2D5", white: "#BAC2DE",
            brightBlack: "#585B70", brightRed: "#F38BA8", brightGreen: "#A6E3A1",
            brightYellow: "#F9E2AF", brightBlue: "#89B4FA", brightMagenta: "#F5C2E7",
            brightCyan: "#94E2D5", brightWhite: "#A6ADC8",
            splitBorder: "#45475A", sidebar: "#181825", tabBar: "#181825"),
        chrome: ChromeColors(
            base: "#11111B", surface: "#181825", elevated: "#1E1E2E", hover: "#313244",
            selected: "#45475A", border: "#45475A", panelBorder: "#313244",
            textPrimary: "#CDD6F4", textSecondary: "#BAC2DE", textTertiary: "#A6ADC8",
            textMuted: "#7F849C", textFaint: "#6C7086", textHelp: "#9399B2"),
        accent: "#CBA6F7")

    public static let all: [AppearanceTheme] =
        [dark, light, tokyoNight, nord, dracula, gruvbox, catppuccin]

    /// Resolve a theme id to its preset (case-insensitive). Unknown ids — and `auto`, which the
    /// caller resolves against the live system appearance before calling here — fall back to `dark`.
    public static func resolve(_ id: String) -> AppearanceTheme {
        let key = id.lowercased()
        return all.first { $0.id == key } ?? dark
    }
}
