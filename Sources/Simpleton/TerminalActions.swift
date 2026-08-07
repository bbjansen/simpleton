// Sources/Simpleton/TerminalActions.swift
import AppKit
import SimpletonCore

final class TerminalActions {

    private let activeSplitController: () -> SplitController?
    private let activeWindowController: () -> WindowController?
    private let windowControllers: () -> [WindowController]
    private let config: () -> AppConfig

    init(
        activeSplitController: @escaping () -> SplitController?,
        activeWindowController: @escaping () -> WindowController?,
        windowControllers: @escaping () -> [WindowController],
        config: @escaping () -> AppConfig
    ) {
        self.activeSplitController = activeSplitController
        self.activeWindowController = activeWindowController
        self.windowControllers = windowControllers
        self.config = config
    }

    // MARK: - Split Actions

    func splitRight() {
        activeSplitController()?.splitFocusedPane(direction: .vertical)
    }

    func splitDown() {
        activeSplitController()?.splitFocusedPane(direction: .horizontal)
    }

    func closePane() {
        guard let sc = activeSplitController() else { return }
        sc.closePane(sc.focusedPaneID)
    }

    func pickLayout() {
        guard let window = NSApp.keyWindow,
            let sc = activeSplitController()
        else { return }

        let alert = NSAlert()
        alert.messageText = "Pick Layout"
        alert.informativeText = "Choose a layout for this tab."
        for layout in PredefinedLayouts.all {
            alert.addButton(withTitle: layout.name)
        }
        alert.addButton(withTitle: "Cancel")

        alert.beginSheetModal(for: window) { response in
            let index = Int(response.rawValue) - Int(NSApplication.ModalResponse.alertFirstButtonReturn.rawValue)
            guard index >= 0, index < PredefinedLayouts.all.count else { return }
            let layout = PredefinedLayouts.all[index]
            sc.applyLayout(layout)
        }
    }

    func togglePaneZoom() {
        activeSplitController()?.toggleZoom()
    }

    func switchToTabN(tag: Int) {
        activeWindowController()?.tabManager.activate(index: tag)
    }

    // MARK: - Focus Navigation

    func focusLeft() { activeSplitController()?.moveFocus(.left) }
    func focusRight() { activeSplitController()?.moveFocus(.right) }
    func focusUp() { activeSplitController()?.moveFocus(.up) }
    func focusDown() { activeSplitController()?.moveFocus(.down) }

    // MARK: - Tab Actions

    func newTab() {
        // Prefer the WindowController owning the key window; fall back to the active/main window's.
        let keyWindow = NSApp.keyWindow
        let wc =
            windowControllers().first(where: { $0.window === keyWindow })
            ?? activeWindowController()
        wc?.newTab()
    }

    /// Close the active tab (⌘W at the tab level). Closing the last tab closes the window.
    func closeTab() {
        guard let wc = closeTargetWindowController(), let active = wc.tabManager.activeItem else {
            NSApp.keyWindow?.close()
            return
        }
        wc.tabManager.close(active.id)
    }

    func nextTab() {
        closeTargetWindowController()?.tabManager.selectNext()
    }

    func prevTab() {
        closeTargetWindowController()?.tabManager.selectPrevious()
    }

    /// The WindowController whose window is key (else the active/main window's).
    private func closeTargetWindowController() -> WindowController? {
        let keyWindow = NSApp.keyWindow
        return windowControllers().first(where: { $0.window === keyWindow }) ?? activeWindowController()
    }

    // MARK: - Font Actions

    func increaseFontSize() {
        guard let sc = activeSplitController() else { return }
        for pane in sc.panes.values {
            let size = pane.terminalView.font.pointSize
            pane.terminalView.font = pane.terminalView.font.withSize(size + 1)
        }
    }

    func decreaseFontSize() {
        guard let sc = activeSplitController() else { return }
        for pane in sc.panes.values {
            let size = pane.terminalView.font.pointSize
            if size > 8 {
                pane.terminalView.font = pane.terminalView.font.withSize(size - 1)
            }
        }
    }

    func resetFontSize() {
        guard let sc = activeSplitController() else { return }
        let defaultSize = CGFloat(config().appearance.fontSize)
        for pane in sc.panes.values {
            pane.terminalView.font = pane.terminalView.font.withSize(defaultSize)
        }
    }
}
