// Sources/Simpleton/ThemeApplier.swift
import AppKit
import SwiftTerm
import SimpletonCore

enum ThemeApplier {

    /// Apply a Theme's colors and font settings to a TerminalView.
    static func apply(theme: Theme, config: AppConfig, to terminalView: TerminalView) {
        let colors = theme.colors

        // Font
        if let font = NSFont(name: config.appearance.fontFamily, size: CGFloat(config.appearance.fontSize)) {
            terminalView.font = font
        } else {
            terminalView.font = NSFont.monospacedSystemFont(ofSize: CGFloat(config.appearance.fontSize), weight: .regular)
        }

        // Core colors
        if let bg = NSColor(hex: colors.background) {
            terminalView.nativeBackgroundColor = bg
        }
        if let fg = NSColor(hex: colors.foreground) {
            terminalView.nativeForegroundColor = fg
        }
        if let cursor = NSColor(hex: colors.cursor) {
            terminalView.caretColor = cursor
        }
        if let selection = NSColor(hex: colors.selection) {
            terminalView.selectedTextBackgroundColor = selection
        }

        // ANSI colors (0-15) — build full 16-color palette and install at once
        let ansiHexes = [
            colors.black, colors.red, colors.green, colors.yellow,
            colors.blue, colors.magenta, colors.cyan, colors.white,
            colors.brightBlack, colors.brightRed, colors.brightGreen, colors.brightYellow,
            colors.brightBlue, colors.brightMagenta, colors.brightCyan, colors.brightWhite,
        ]
        let palette = ansiHexes.compactMap { hex -> Color? in
            guard let nsColor = NSColor(hex: hex),
                  let rgb = nsColor.usingColorSpace(.deviceRGB) else { return nil }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
            return Color(red: UInt16(r * 65535), green: UInt16(g * 65535), blue: UInt16(b * 65535))
        }
        if palette.count == 16 {
            terminalView.installColors(palette)
        }
    }
}

// MARK: - NSColor hex extension

extension NSColor {
    convenience init?(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") {
            hexString.removeFirst()
        }
        guard hexString.count == 6 else { return nil }

        var rgb: UInt64 = 0
        guard Scanner(string: hexString).scanHexInt64(&rgb) else { return nil }

        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
