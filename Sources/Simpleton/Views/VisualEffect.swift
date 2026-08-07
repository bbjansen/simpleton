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

/// A hairline divider tinted from the theme's border token, so panel section rules match the
/// themed chrome instead of the system separator gray.
struct ThemedDivider: View {
    var body: some View {
        Rectangle()
            .fill(DT.border.opacity(0.6))
            .frame(height: 1)
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
                color.opacity(tint ?? ThemeSettings.shared.chromeOpacity)
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
                color.opacity(min(1.0, ThemeSettings.shared.chromeOpacity + 0.22))
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
    @ViewBuilder
    func frostedPanel(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.10), lineWidth: 1))
        } else {
            self.background(VisualEffect(material: .hudWindow, blendingMode: .behindWindow))
                .clipShape(shape)
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
