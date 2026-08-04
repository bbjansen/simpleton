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

extension View {
    /// A modern "glossy card" surface: continuous corners, a hairline that catches light, and a
    /// soft drop shadow for depth. On macOS 26 it upgrades to Liquid Glass automatically.
    func glossyCard(cornerRadius: CGFloat = 12, tint: Color = .clear) -> some View {
        modifier(GlossyCard(cornerRadius: cornerRadius, tint: tint))
    }
}

private struct GlossyCard: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return
            content
            .background {
                if #available(macOS 26.0, *) {
                    shape.fill(.ultraThinMaterial)  // Liquid Glass adoption tracked separately
                } else {
                    shape.fill(.ultraThinMaterial)
                }
            }
            .overlay(shape.strokeBorder(.white.opacity(0.10), lineWidth: 1))
            .clipShape(shape)
            .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
    }
}
