// Sources/SimpletonCore/Models/ThemePalette.swift
import Foundation

/// The built-in whole-app appearance themes. Dark/Light reproduce the pre-theme look exactly;
/// the colored themes are "pop-out" schemes in the spirit of Slack's sidebar themes — the chrome
/// (sidebar, activity bars, panels) is a fully saturated color with white text and a bright accent
/// for the active item, while the terminal stays a readable hue-tinted dark.
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

    // MARK: - Pop-out colored themes (saturated chrome, à la Slack)

    /// Deep aubergine purple — Slack's signature look.
    public static let grape = AppearanceTheme(
        id: "grape", name: "Grape", isDark: true,
        terminal: ThemeColors(
            background: "#1C132B", foreground: "#ECE1F5", cursor: "#C77DFF", selection: "#3F2A55",
            black: "#2A1F3D", red: "#FF6E9C", green: "#6EE7A8", yellow: "#F5C97B",
            blue: "#A78BFA", magenta: "#E879F9", cyan: "#7DD3FC", white: "#D4C5E0",
            brightBlack: "#6C5A80", brightRed: "#FF8AB0", brightGreen: "#8CF0BE",
            brightYellow: "#FFDA9A", brightBlue: "#C4B0FF", brightMagenta: "#F5A0FF",
            brightCyan: "#A4E8FF", brightWhite: "#FFFFFF",
            splitBorder: "#5B2A66", sidebar: "#4A154B", tabBar: "#4A154B"),
        chrome: ChromeColors(
            base: "#2E0A3A", surface: "#4A154B", elevated: "#5B2A66", hover: "#642273",
            selected: "#833C99", border: "#6D2E7E", panelBorder: "#3A0F4A",
            textPrimary: "#FFFFFF", textSecondary: "#ECD9F2", textTertiary: "#CBA9D8",
            textMuted: "#A882B4", textFaint: "#875F94", textHelp: "#CBA9D8"),
        accent: "#D08BFF")

    /// Rich tangerine orange — the chrome is genuinely orange, not brown.
    public static let tangerine = AppearanceTheme(
        id: "tangerine", name: "Tangerine", isDark: true,
        terminal: ThemeColors(
            background: "#1F140C", foreground: "#F7E9DB", cursor: "#FFB454", selection: "#4A2E17",
            black: "#33241A", red: "#FF6E6E", green: "#B8D96B", yellow: "#FFC55C",
            blue: "#5CB8E8", magenta: "#F58BC0", cyan: "#5FD1C4", white: "#E8D5C4",
            brightBlack: "#8A6A52", brightRed: "#FF8A8A", brightGreen: "#CDEB86",
            brightYellow: "#FFD98A", brightBlue: "#82CFF5", brightMagenta: "#FFA8D4",
            brightCyan: "#86E8DC", brightWhite: "#FFFFFF",
            splitBorder: "#B8480E", sidebar: "#D2500A", tabBar: "#D2500A"),
        chrome: ChromeColors(
            base: "#7C2D12", surface: "#D2500A", elevated: "#B8480E", hover: "#E85D14",
            selected: "#F97316", border: "#EA6A2A", panelBorder: "#8A340F",
            textPrimary: "#FFFFFF", textSecondary: "#FFE7D4", textTertiary: "#FFCEAA",
            textMuted: "#F3B085", textFaint: "#D19468", textHelp: "#FFCEAA"),
        accent: "#FFD166")

    /// Vivid emerald green.
    public static let emerald = AppearanceTheme(
        id: "emerald", name: "Emerald", isDark: true,
        terminal: ThemeColors(
            background: "#0A1712", foreground: "#DDF5EA", cursor: "#5EEAD4", selection: "#123A2A",
            black: "#16281F", red: "#FF7A7A", green: "#54E39B", yellow: "#EEDA7A",
            blue: "#6FB8F5", magenta: "#E58BD0", cyan: "#5EEAD4", white: "#CFE8DD",
            brightBlack: "#4E7A66", brightRed: "#FF9A9A", brightGreen: "#79F5B6",
            brightYellow: "#FFEB9E", brightBlue: "#97D0FF", brightMagenta: "#FFA8E4",
            brightCyan: "#8CF5E4", brightWhite: "#FFFFFF",
            splitBorder: "#0A6640", sidebar: "#0B7A4B", tabBar: "#0B7A4B"),
        chrome: ChromeColors(
            base: "#06301F", surface: "#0B7A4B", elevated: "#0A6640", hover: "#0E9159",
            selected: "#10B981", border: "#138A5C", panelBorder: "#07402A",
            textPrimary: "#FFFFFF", textSecondary: "#D2F5E6", textTertiary: "#A7E9CE",
            textMuted: "#79C9A6", textFaint: "#5AA588", textHelp: "#A7E9CE"),
        accent: "#6EE7B7")

    /// Bold sapphire blue.
    public static let sapphire = AppearanceTheme(
        id: "sapphire", name: "Sapphire", isDark: true,
        terminal: ThemeColors(
            background: "#0C1526", foreground: "#E2ECFB", cursor: "#7DD3FC", selection: "#1E355E",
            black: "#1A2740", red: "#FF7A8F", green: "#6FE0A0", yellow: "#F0D284",
            blue: "#6AA8FF", magenta: "#C4A0FF", cyan: "#7DD3FC", white: "#CFDCF0",
            brightBlack: "#4E668F", brightRed: "#FF9AAB", brightGreen: "#8CF0BC",
            brightYellow: "#FFE49E", brightBlue: "#97C2FF", brightMagenta: "#D8BCFF",
            brightCyan: "#A4E8FF", brightWhite: "#FFFFFF",
            splitBorder: "#23458A", sidebar: "#1E4F9C", tabBar: "#1E4F9C"),
        chrome: ChromeColors(
            base: "#0A2A5E", surface: "#1E4F9C", elevated: "#23458A", hover: "#2A5FB8",
            selected: "#3B82F6", border: "#2E5DAE", panelBorder: "#123163",
            textPrimary: "#FFFFFF", textSecondary: "#D9E6FF", textTertiary: "#AEC8F5",
            textMuted: "#83A4DC", textFaint: "#6485BE", textHelp: "#AEC8F5"),
        accent: "#7DD3FC")

    /// Deep ruby / raspberry.
    public static let ruby = AppearanceTheme(
        id: "ruby", name: "Ruby", isDark: true,
        terminal: ThemeColors(
            background: "#220D16", foreground: "#F9E1E9", cursor: "#FB7185", selection: "#4E1428",
            black: "#361420", red: "#FF7A93", green: "#8ED98C", yellow: "#F2C97A",
            blue: "#8FB8F0", magenta: "#FF8AC4", cyan: "#7BD6D0", white: "#E8CFD8",
            brightBlack: "#8A5064", brightRed: "#FF9AAE", brightGreen: "#AEEAAC",
            brightYellow: "#FFE09A", brightBlue: "#AECCF7", brightMagenta: "#FFA8D8",
            brightCyan: "#9CE8E2", brightWhite: "#FFFFFF",
            splitBorder: "#8E1A42", sidebar: "#A81E4D", tabBar: "#A81E4D"),
        chrome: ChromeColors(
            base: "#4A0A25", surface: "#A81E4D", elevated: "#8E1A42", hover: "#C22659",
            selected: "#E11D6B", border: "#B83059", panelBorder: "#5E1230",
            textPrimary: "#FFFFFF", textSecondary: "#FBD6E4", textTertiary: "#F2AEC7",
            textMuted: "#D983A4", textFaint: "#BC6486", textHelp: "#F2AEC7"),
        accent: "#FB7185")

    /// Deep teal.
    public static let teal = AppearanceTheme(
        id: "teal", name: "Teal", isDark: true,
        terminal: ThemeColors(
            background: "#08201E", foreground: "#D6F0EC", cursor: "#2DD4BF", selection: "#10403A",
            black: "#143A36", red: "#FF7A8A", green: "#4FD6B0", yellow: "#E8D07A",
            blue: "#5FB8E0", magenta: "#D48BD0", cyan: "#2DD4BF", white: "#C8E6E1",
            brightBlack: "#4A7A73", brightRed: "#FF9AA6", brightGreen: "#79E8C8",
            brightYellow: "#FFE49E", brightBlue: "#8CD4F0", brightMagenta: "#F0A8EC",
            brightCyan: "#6EEAD8", brightWhite: "#FFFFFF",
            splitBorder: "#0A5A54", sidebar: "#0F766E", tabBar: "#0F766E"),
        chrome: ChromeColors(
            base: "#06423C", surface: "#0F766E", elevated: "#0C5F58", hover: "#12897F",
            selected: "#14B8A6", border: "#17897E", panelBorder: "#084A44",
            textPrimary: "#FFFFFF", textSecondary: "#CFF0EB", textTertiary: "#A0DDD5",
            textMuted: "#74C0B6", textFaint: "#56A197", textHelp: "#A0DDD5"),
        accent: "#5EEAD4")

    /// Deep indigo.
    public static let indigo = AppearanceTheme(
        id: "indigo", name: "Indigo", isDark: true,
        terminal: ThemeColors(
            background: "#12122E", foreground: "#E0E0F8", cursor: "#A5B4FC", selection: "#2A2A5E",
            black: "#20204A", red: "#FF7A9C", green: "#7AE0A0", yellow: "#F0D284",
            blue: "#818CF8", magenta: "#C4A0FF", cyan: "#7DD3FC", white: "#CFCFF0",
            brightBlack: "#5450A0", brightRed: "#FF9AB8", brightGreen: "#9CF0BE",
            brightYellow: "#FFE49E", brightBlue: "#A5B4FC", brightMagenta: "#D8BCFF",
            brightCyan: "#A4E8FF", brightWhite: "#FFFFFF",
            splitBorder: "#3730A3", sidebar: "#4338CA", tabBar: "#4338CA"),
        chrome: ChromeColors(
            base: "#26216B", surface: "#4338CA", elevated: "#3A32A8", hover: "#4E44E0",
            selected: "#6366F1", border: "#4F46B8", panelBorder: "#2A2480",
            textPrimary: "#FFFFFF", textSecondary: "#DAD8FA", textTertiary: "#B4B0F0",
            textMuted: "#8B86DC", textFaint: "#6B66BE", textHelp: "#B4B0F0"),
        accent: "#A5B4FC")

    /// Fire crimson.
    public static let crimson = AppearanceTheme(
        id: "crimson", name: "Crimson", isDark: true,
        terminal: ThemeColors(
            background: "#2A0E0E", foreground: "#F8DEDE", cursor: "#FCA5A5", selection: "#5E1A1A",
            black: "#3E1616", red: "#FF6E6E", green: "#A8D98C", yellow: "#F2C97A",
            blue: "#8FB8F0", magenta: "#F58BC0", cyan: "#7BD6D0", white: "#E8CFCF",
            brightBlack: "#8A5050", brightRed: "#FF9A9A", brightGreen: "#C4EBAC",
            brightYellow: "#FFE09A", brightBlue: "#AECCF7", brightMagenta: "#FFA8D4",
            brightCyan: "#9CE8E2", brightWhite: "#FFFFFF",
            splitBorder: "#991B1B", sidebar: "#B91C1C", tabBar: "#B91C1C"),
        chrome: ChromeColors(
            base: "#5E1010", surface: "#B91C1C", elevated: "#9E1818", hover: "#D42525",
            selected: "#EF4444", border: "#C33030", panelBorder: "#6E1212",
            textPrimary: "#FFFFFF", textSecondary: "#FBD9D9", textTertiary: "#F2ABAB",
            textMuted: "#DC8383", textFaint: "#BE6464", textHelp: "#F2ABAB"),
        accent: "#FCA5A5")

    /// Electric magenta.
    public static let magenta = AppearanceTheme(
        id: "magenta", name: "Magenta", isDark: true,
        terminal: ThemeColors(
            background: "#260A2A", foreground: "#F5DAF5", cursor: "#E879F9", selection: "#4E1454",
            black: "#3A1440", red: "#FF6E9C", green: "#6EE7A8", yellow: "#F5C97B",
            blue: "#A78BFA", magenta: "#E879F9", cyan: "#7DD3FC", white: "#E4CFE6",
            brightBlack: "#8A5090", brightRed: "#FF8AB0", brightGreen: "#8CF0BE",
            brightYellow: "#FFDA9A", brightBlue: "#C4B0FF", brightMagenta: "#F5A0FF",
            brightCyan: "#A4E8FF", brightWhite: "#FFFFFF",
            splitBorder: "#86198F", sidebar: "#A21CAF", tabBar: "#A21CAF"),
        chrome: ChromeColors(
            base: "#560A5E", surface: "#A21CAF", elevated: "#8A1896", hover: "#B825C6",
            selected: "#D946EF", border: "#B030BC", panelBorder: "#630E6B",
            textPrimary: "#FFFFFF", textSecondary: "#F5D6F7", textTertiary: "#E8AEEE",
            textMuted: "#D083DC", textFaint: "#B664C4", textHelp: "#E8AEEE"),
        accent: "#F0ABFC")

    /// Deep gold / amber.
    public static let gold = AppearanceTheme(
        id: "gold", name: "Gold", isDark: true,
        terminal: ThemeColors(
            background: "#211803", foreground: "#F5EAD0", cursor: "#FBBF24", selection: "#4A3810",
            black: "#35280C", red: "#FF8A6E", green: "#C4D96B", yellow: "#FBBF24",
            blue: "#6BC0E0", magenta: "#E8A0C4", cyan: "#6ED1C4", white: "#E8DCC0",
            brightBlack: "#8A7040", brightRed: "#FFA98A", brightGreen: "#DCEB86",
            brightYellow: "#FFD54A", brightBlue: "#8CD4F0", brightMagenta: "#FFBCDC",
            brightCyan: "#8CE8DC", brightWhite: "#FFFFFF",
            splitBorder: "#854D0E", sidebar: "#A16207", tabBar: "#A16207"),
        chrome: ChromeColors(
            base: "#5E3A06", surface: "#A16207", elevated: "#855107", hover: "#B87308",
            selected: "#EAB308", border: "#B37A1A", panelBorder: "#6B4206",
            textPrimary: "#FFFFFF", textSecondary: "#F5E4C4", textTertiary: "#EACFA0",
            textMuted: "#D4B579", textFaint: "#B8975A", textHelp: "#EACFA0"),
        accent: "#FCD34D")

    /// Cool slate — the most restrained of the colored set.
    public static let slate = AppearanceTheme(
        id: "slate", name: "Slate", isDark: true,
        terminal: ThemeColors(
            background: "#14181F", foreground: "#DDE3EC", cursor: "#94A3B8", selection: "#2E3644",
            black: "#222835", red: "#FF7A8F", green: "#6FE0A0", yellow: "#F0D284",
            blue: "#7DABF0", magenta: "#C4A0E8", cyan: "#7DD3FC", white: "#CFD6E0",
            brightBlack: "#5A6577", brightRed: "#FF9AAB", brightGreen: "#8CF0BC",
            brightYellow: "#FFE49E", brightBlue: "#A5C8FF", brightMagenta: "#D8BCF0",
            brightCyan: "#A4E8FF", brightWhite: "#FFFFFF",
            splitBorder: "#334155", sidebar: "#3F4A5C", tabBar: "#3F4A5C"),
        chrome: ChromeColors(
            base: "#232B37", surface: "#3F4A5C", elevated: "#34404F", hover: "#4A576B",
            selected: "#64748B", border: "#4E5A6E", panelBorder: "#29313D",
            textPrimary: "#FFFFFF", textSecondary: "#DCE2EC", textTertiary: "#B4BECC",
            textMuted: "#8A94A6", textFaint: "#6B7488", textHelp: "#B4BECC"),
        accent: "#94A3B8")

    public static let all: [AppearanceTheme] =
        [
            dark, light, grape, tangerine, emerald, sapphire, ruby,
            teal, indigo, crimson, magenta, gold, slate,
        ]

    /// Resolve a theme id to its preset (case-insensitive). Unknown ids — and `auto`, which the
    /// caller resolves against the live system appearance before calling here — fall back to `dark`.
    public static func resolve(_ id: String) -> AppearanceTheme {
        let key = id.lowercased()
        return all.first { $0.id == key } ?? dark
    }
}
