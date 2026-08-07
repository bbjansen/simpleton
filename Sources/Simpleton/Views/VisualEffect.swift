// Sources/Simpleton/Views/VisualEffect.swift
import AppKit
import SwiftUI

/// A SwiftUI wrapper around `NSVisualEffectView` for real macOS vibrancy/translucency.
/// Use `.behindWindow` blending to blur the desktop behind the window (native sidebar look),
/// or `.withinWindow` to frost content inside the window.
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var isEmphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active  // stay vibrant even when the window is not key
        view.isEmphasized = isEmphasized
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.isEmphasized = isEmphasized
    }
}

extension NSVisualEffectView {
    /// Build a full-bleed vibrancy backdrop configured for behind-window blur.
    static func backdrop(material: Material = .underWindowBackground) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }
}

/// A hairline section rule for panel/AI-chrome. A soft *recessed groove* (a faint dark line with a
/// faint light lip beneath it) rather than a tinted line: on the saturated colored/gradient themes a
/// theme-tinted border reads as a harsh glowing bar, so we match the header/tab-strip house style
/// (`.black.opacity(~0.18)`) which sits back on every theme and still separates cleanly on dark/light.
struct ThemedDivider: View {
    var body: some View {
        Rectangle()
            .fill(.black.opacity(0.16))
            .frame(height: 1)
            .overlay(
                Rectangle().fill(.white.opacity(0.05)).frame(height: 1),
                alignment: .bottom)
    }
}

extension ThemeSettings {
    /// The chrome gradient colors for the active theme (top→bottom stops), or nil for a solid theme.
    var chromeGradientColors: [Color]? {
        guard let stops = theme.gradient, stops.count >= 2 else { return nil }
        let colors = stops.compactMap { Color(hex: $0) }
        return colors.count >= 2 ? colors : nil
    }
}

/// The theme-color wash under the chrome vibrancy: a diagonal gradient blend when the active theme
/// defines one, otherwise the flat surface color. Read from `ThemeSettings.shared` at render time, so
/// it flips with the theme (its host views observe ThemeSettings and re-render on a switch).
private struct ThemeWash: View {
    let color: Color
    let opacity: Double
    var body: some View {
        Group {
            if let colors = ThemeSettings.shared.chromeGradientColors {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                color
            }
        }
        .opacity(opacity)
    }
}

extension View {
    /// Bold theme-colored macOS glass. A vibrancy blur provides the polished translucent "gloss";
    /// a dominant theme-color wash on top makes the surface read as *fully* the theme's color, and a
    /// soft top highlight gives it a glassy sheen. Used for the sidebar and activity bars so every
    /// theme is visibly, fully its color instead of a neutral system gray. `tint` trades color
    /// boldness (higher) against visible blur (lower).
    func themedGlass(_ color: Color, tint: Double? = nil) -> some View {
        background {
            ZStack {
                VisualEffect(material: .sidebar, blendingMode: .behindWindow)
                ThemeWash(color: color, opacity: tint ?? ThemeSettings.shared.chromeOpacity)
                LinearGradient(
                    colors: [.white.opacity(0.10), .clear, .black.opacity(0.07)],
                    startPoint: .top, endPoint: .bottom)
            }
        }
    }

    /// The top header bar's surface. Uses the same vibrancy base as `themedGlass` (so the header,
    /// rails, and sidebar read as one continuous chrome), but pushes the theme-color wash *more
    /// opaque* than the rails so the traffic lights sit on a solid, cohesive band instead of a
    /// washed-out translucent strip — and drops the top highlight (which made the traffic-light row
    /// look like a separate lighter bar / "floating"). A faint bottom shade grounds the bar against
    /// the content below.
    func themedHeader(_ color: Color) -> some View {
        background {
            ZStack {
                VisualEffect(material: .sidebar, blendingMode: .behindWindow)
                // Denser color than the rails' chromeOpacity so the bar is unmistakably one surface.
                ThemeWash(color: color, opacity: min(1.0, ThemeSettings.shared.chromeOpacity + 0.22))
                LinearGradient(
                    colors: [.clear, .black.opacity(0.06)],
                    startPoint: .top, endPoint: .bottom)
            }
        }
    }

    /// A modern "glossy card" surface: continuous corners, a hairline that catches light, and a
    /// soft drop shadow for depth. On macOS 26 it upgrades to Liquid Glass automatically.
    func glossyCard(cornerRadius: CGFloat = 12, tint: Color = .clear) -> some View {
        modifier(GlossyCard(cornerRadius: cornerRadius, tint: tint))
    }

    /// A floating panel surface (command palette, quick connect): real Liquid Glass on macOS 26,
    /// frosted `.hudWindow` vibrancy on macOS 14/15. Both get a continuous-corner clip + hairline.
    /// A theme-color wash sits on top of the frosted glass (behind the panel content) so the dialog
    /// reads as the active theme — the same `ThemeWash` the chrome uses — instead of a neutral gray.
    /// Read from `ThemeSettings.shared` at render time, so it flips live with the theme (the content
    /// views already observe ThemeSettings and re-render on a switch).
    @ViewBuilder
    func frostedPanel(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        // The theme-color wash, clipped to the panel shape, painted on top of the frosted glass so the
        // dialog takes the theme's color. Same layering as `themedGlass`: vibrancy at the back, wash on
        // top of it, panel content above.
        let wash = ThemeWash(color: DT.surface, opacity: ThemeSettings.shared.chromeOpacity)
            .clipShape(shape)
            .allowsHitTesting(false)
        if #available(macOS 26.0, *) {
            self.background {
                Color.clear
                    .glassEffect(.regular, in: shape)
                    .overlay(wash)
            }
            .overlay(shape.strokeBorder(.white.opacity(0.10), lineWidth: 1))
        } else {
            self.background {
                VisualEffect(material: .hudWindow, blendingMode: .behindWindow)
                    .overlay(wash)
                    .clipShape(shape)
            }
            .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 1))
        }
    }
}

private struct GlossyCard: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            // Real Liquid Glass on Tahoe — reflects/refracts content behind it.
            content.glassEffect(.regular, in: shape)
        } else {
            // Graceful fallback on macOS 14/15: frosted material + hairline + soft shadow.
            content
                .background(shape.fill(.ultraThinMaterial))
                .overlay(shape.strokeBorder(.white.opacity(0.10), lineWidth: 1))
                .clipShape(shape)
                .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
        }
    }
}
