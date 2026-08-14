import CoreGraphics
import SimpletonCore

func runSQLWorkspaceLayoutChecks(_ t: TestRunner) {
    typealias D = SQLWorkspaceLayoutDefaults

    t.suite("SQLWorkspaceLayoutDefaults.defaults in range") {
        t.expect(
            D.sidebarWidth >= D.minSidebarWidth && D.sidebarWidth <= D.maxSidebarWidth,
            "default sidebar width within clamp range")
        t.expect(
            D.editorSplitFraction >= D.minEditorSplitFraction
                && D.editorSplitFraction <= D.maxEditorSplitFraction,
            "default split fraction within clamp range")
        t.expect(!D.sidebarCollapsed, "sidebar visible by default")
    }

    t.suite("SQLWorkspaceLayoutDefaults.clampSidebarWidth") {
        t.expectEqual(D.clampSidebarWidth(50), D.minSidebarWidth, "below min → min")
        t.expectEqual(D.clampSidebarWidth(9999), D.maxSidebarWidth, "above max → max")
        t.expectEqual(D.clampSidebarWidth(300), 300, "in range → unchanged")
        t.expectEqual(D.clampSidebarWidth(.nan), D.sidebarWidth, "non-finite → default")
        t.expectEqual(D.clampSidebarWidth(.infinity), D.sidebarWidth, "infinite → default")
    }

    t.suite("SQLWorkspaceLayoutDefaults.clampEditorSplitFraction") {
        t.expectEqual(D.clampEditorSplitFraction(0.01), D.minEditorSplitFraction, "below min → min")
        t.expectEqual(D.clampEditorSplitFraction(0.99), D.maxEditorSplitFraction, "above max → max")
        t.expectEqual(D.clampEditorSplitFraction(0.6), 0.6, "in range → unchanged")
        t.expectEqual(D.clampEditorSplitFraction(.nan), D.editorSplitFraction, "non-finite → default")
    }

    t.suite("SQLWorkspaceLayoutDefaults.keys") {
        t.expectEqual(D.sidebarWidthKey, "sqlWorkspace.sidebarWidth", "sidebar width key")
        t.expectEqual(D.sidebarCollapsedKey, "sqlWorkspace.sidebarCollapsed", "sidebar collapsed key")
        t.expectEqual(D.editorSplitKey, "sqlWorkspace.editorSplitFraction", "editor split key")
    }
}
