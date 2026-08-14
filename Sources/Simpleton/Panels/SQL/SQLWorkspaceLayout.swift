// Sources/Simpleton/Panels/SQL/SQLWorkspaceLayout.swift
import SimpletonCore
import SwiftUI

/// Persisted layout for `SQLWorkspaceView`: the schema-sidebar width, the sidebar-collapsed flag, and
/// the editor/results split fraction — all backed by `@AppStorage` (UserDefaults) so proportions and
/// collapse state survive reopening the window and relaunching the app. The numeric policy (defaults,
/// clamp ranges, and the persistence keys) lives in the pure, headless `SQLWorkspaceLayoutDefaults`
/// in SimpletonCore so it can be checked without a UI; this type is the thin `@AppStorage` wrapper.
///
/// `@AppStorage` stores `Double`/`Bool`; the view works in `CGFloat`, so the exposed values bridge.
final class SQLWorkspaceLayout: ObservableObject {

    @AppStorage(SQLWorkspaceLayoutDefaults.sidebarWidthKey)
    private var storedSidebarWidth: Double = Double(SQLWorkspaceLayoutDefaults.sidebarWidth)

    @AppStorage(SQLWorkspaceLayoutDefaults.sidebarCollapsedKey)
    private var storedSidebarCollapsed: Bool = SQLWorkspaceLayoutDefaults.sidebarCollapsed

    @AppStorage(SQLWorkspaceLayoutDefaults.editorSplitKey)
    private var storedEditorSplitFraction: Double = Double(SQLWorkspaceLayoutDefaults.editorSplitFraction)

    /// Republish so SwiftUI re-renders on a change (the `@AppStorage` wrappers here are not observed by
    /// SwiftUI directly since this object owns them rather than a view).
    private func changed() { objectWillChange.send() }

    var sidebarWidth: CGFloat {
        get { SQLWorkspaceLayoutDefaults.clampSidebarWidth(CGFloat(storedSidebarWidth)) }
        set {
            changed()
            storedSidebarWidth = Double(SQLWorkspaceLayoutDefaults.clampSidebarWidth(newValue))
        }
    }

    var sidebarCollapsed: Bool {
        get { storedSidebarCollapsed }
        set {
            changed()
            storedSidebarCollapsed = newValue
        }
    }

    var editorSplitFraction: CGFloat {
        get { SQLWorkspaceLayoutDefaults.clampEditorSplitFraction(CGFloat(storedEditorSplitFraction)) }
        set {
            changed()
            storedEditorSplitFraction = Double(SQLWorkspaceLayoutDefaults.clampEditorSplitFraction(newValue))
        }
    }

    /// Clamp helpers the view calls before assigning during a drag.
    func clampedSidebarWidth(_ width: CGFloat) -> CGFloat {
        SQLWorkspaceLayoutDefaults.clampSidebarWidth(width)
    }

    func clampedEditorSplitFraction(_ fraction: CGFloat) -> CGFloat {
        SQLWorkspaceLayoutDefaults.clampEditorSplitFraction(fraction)
    }
}
