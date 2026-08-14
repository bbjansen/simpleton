// Sources/SimpletonCore/Models/SQLWorkspaceLayout.swift
import CoreGraphics

/// Pure defaults + clamping for the SQL workspace's persisted layout: the schema sidebar width, the
/// sidebar-collapsed flag, and the editor/results vertical split fraction. The SwiftUI layer wraps
/// these values in `@AppStorage` (see `SQLWorkspaceLayout` in the app target); this enum keeps the
/// numeric policy pure and headless so CoreChecks can verify the defaults and clamping without a UI.
public enum SQLWorkspaceLayoutDefaults {

    // MARK: Persistence keys (single source of truth, shared with the @AppStorage wrapper)

    public static let sidebarWidthKey = "sqlWorkspace.sidebarWidth"
    public static let sidebarCollapsedKey = "sqlWorkspace.sidebarCollapsed"
    public static let editorSplitKey = "sqlWorkspace.editorSplitFraction"

    // MARK: Defaults

    /// Default schema-sidebar width in points (~18% of a ~1000pt workspace, per the design).
    public static let sidebarWidth: CGFloat = 220
    /// Default: sidebar visible.
    public static let sidebarCollapsed = false
    /// Default editor/results split: the editor takes the top half.
    public static let editorSplitFraction: CGFloat = 0.5

    // MARK: Clamp ranges

    /// The sidebar never renders narrower than this when visible (collapsing is a separate flag).
    public static let minSidebarWidth: CGFloat = 140
    public static let maxSidebarWidth: CGFloat = 480
    /// Keep both the editor and the results readable — neither half collapses past these fractions.
    public static let minEditorSplitFraction: CGFloat = 0.15
    public static let maxEditorSplitFraction: CGFloat = 0.85

    // MARK: Clamping (pure)

    /// Clamp a persisted/dragged sidebar width into `[minSidebarWidth, maxSidebarWidth]`, mapping a
    /// non-finite stored value (never written, but defensively handled) back to the default.
    public static func clampSidebarWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite else { return sidebarWidth }
        return min(max(width, minSidebarWidth), maxSidebarWidth)
    }

    /// Clamp a split fraction into `[minEditorSplitFraction, maxEditorSplitFraction]`, mapping a
    /// non-finite stored value back to the default.
    public static func clampEditorSplitFraction(_ fraction: CGFloat) -> CGFloat {
        guard fraction.isFinite else { return editorSplitFraction }
        return min(max(fraction, minEditorSplitFraction), maxEditorSplitFraction)
    }
}
