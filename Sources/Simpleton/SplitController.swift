// Sources/Simpleton/SplitController.swift
import AppKit
import SwiftTerm
import SimpletonCore

/// Owns the split tree for one tab. Reconciles the logical SplitNode tree to an
/// NSSplitView hierarchy. Creates/destroys PaneControllers as panes are added/removed.
final class SplitController: NSObject, NSSplitViewDelegate {

    /// The logical tree. Set this to trigger reconciliation.
    private(set) var tree: SplitNode

    /// Registry: PaneID → PaneController
    private(set) var panes: [PaneID: PaneController] = [:]

    /// The root view (either a single TerminalView or an NSSplitView).
    private(set) var rootView: NSView

    /// Currently focused pane.
    private(set) var focusedPaneID: PaneID

    /// Factory for creating new PaneControllers.
    var paneFactory: ((PaneID) -> PaneController)?

    /// Called when a pane requests to be closed.
    var onPaneClose: ((PaneID) -> Void)?

    /// Called when focused pane changes.
    var onFocusChange: ((PaneID) -> Void)?

    /// Called when the split tree changes (pane added, removed, layout changed).
    var onTreeChange: (() -> Void)?

    /// Saved tree for pane zoom (Cmd+Shift+Enter).
    private var savedTree: SplitNode?
    private(set) var zoomedPaneID: PaneID?

    init(initialPaneController: PaneController) {
        self.tree = .pane(initialPaneController.id)
        self.focusedPaneID = initialPaneController.id
        self.panes = [initialPaneController.id: initialPaneController]
        self.rootView = initialPaneController.terminalView
        super.init()
    }

    // MARK: - Public API

    /// Split the focused pane in the given direction.
    func splitFocusedPane(direction: SplitDirection) {
        guard let factory = paneFactory else { return }

        let newPaneID = UUID()
        let (newTree, _) = SplitTreeOperations.splitPane(
            in: tree,
            paneID: focusedPaneID,
            direction: direction,
            newPaneID: newPaneID
        )

        // Create the new pane controller
        let newPane = factory(newPaneID)
        panes[newPaneID] = newPane

        // Apply the new tree
        tree = newTree
        reconcile()

        // Focus the new pane
        setFocus(to: newPaneID)
        NotificationCenter.default.post(name: .simpletonSplitChanged, object: nil)
        onTreeChange?()
    }

    /// Close a specific pane. If it's the last pane, calls onPaneClose.
    /// Shows a confirmation alert when the pane has a running process.
    func closePane(_ paneID: PaneID) {
        // Confirm before closing a pane with a running process
        if let pane = panes[paneID], pane.state == .running,
           let window = pane.terminalView.window {
            let alert = NSAlert()
            alert.messageText = "Close this pane?"
            alert.informativeText = "A process is still running in this pane. Are you sure you want to close it?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Close")
            alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertFirstButtonReturn {
                    self?.performClosePane(paneID)
                }
            }
            return
        }
        performClosePane(paneID)
    }

    /// Internal close logic after any confirmation has been accepted.
    private func performClosePane(_ paneID: PaneID) {
        guard let newTree = SplitTreeOperations.closePane(in: tree, paneID: paneID) else {
            // Last pane — notify delegate
            onPaneClose?(paneID)
            return
        }

        // Remove the pane controller
        panes[paneID]?.terminalView.removeFromSuperview()
        panes.removeValue(forKey: paneID)

        // If focused pane was closed, move focus
        if focusedPaneID == paneID {
            if let firstPane = newTree.allPaneIDs.first {
                focusedPaneID = firstPane
            }
        }

        tree = newTree
        reconcile()
        setFocus(to: focusedPaneID)
        NotificationCenter.default.post(name: .simpletonSplitChanged, object: nil)
        onTreeChange?()
    }

    /// Navigate focus in a direction.
    func moveFocus(_ direction: NavigationDirection) {
        if let target = SplitTreeOperations.adjacentPane(in: tree, from: focusedPaneID, direction: direction) {
            setFocus(to: target)
        }
    }

    /// Apply a predefined layout. Keeps the focused pane, creates new panes for the rest.
    func applyLayout(_ layout: PredefinedLayout) {
        guard let factory = paneFactory else { return }

        let (newTree, paneIDs) = SplitTreeOperations.applyLayout(layout, existingPaneID: focusedPaneID)

        // Remove all panes except the focused one
        for (id, pane) in panes where id != focusedPaneID {
            pane.terminalView.removeFromSuperview()
        }
        guard let keptPane = panes[focusedPaneID] else { return }
        panes = [focusedPaneID: keptPane]

        // Create new pane controllers for new IDs
        for id in paneIDs where id != focusedPaneID {
            panes[id] = factory(id)
        }

        tree = newTree
        reconcile()
        setFocus(to: focusedPaneID)
        NotificationCenter.default.post(name: .simpletonSplitChanged, object: nil)
        onTreeChange?()
    }

    // MARK: - Zoom

    func toggleZoom() {
        if let _ = zoomedPaneID {
            // Unzoom: restore saved tree
            guard let saved = savedTree else { return }
            tree = saved
            savedTree = nil
            zoomedPaneID = nil
            reconcile()
            setFocus(to: focusedPaneID)
            onTreeChange?()
        } else {
            // Zoom: save tree, show only focused pane
            guard tree.paneCount > 1 else { return }
            savedTree = tree
            zoomedPaneID = focusedPaneID
            tree = .pane(focusedPaneID)
            reconcile()
            onTreeChange?()
        }
    }

    // MARK: - Focus

    func setFocus(to paneID: PaneID) {
        focusedPaneID = paneID
        if let pane = panes[paneID] {
            pane.terminalView.window?.makeFirstResponder(pane.terminalView)
            onFocusChange?(paneID)
        }

        // Highlight the focused pane with a blue border when there are 2+ panes
        let showBorder = panes.count >= 2
        for (id, pane) in panes {
            pane.terminalView.wantsLayer = true
            if showBorder && id == paneID {
                pane.terminalView.layer?.borderWidth = 2
                pane.terminalView.layer?.borderColor = NSColor.systemBlue.cgColor
            } else {
                pane.terminalView.layer?.borderWidth = 0
                pane.terminalView.layer?.borderColor = nil
            }
        }
    }

    // MARK: - Reconciliation

    /// Rebuild the NSSplitView hierarchy from the logical tree.
    private func reconcile() {
        let parentView = rootView.superview
        let frame = rootView.frame

        // Track position in parent's arranged subviews before removal
        // so the terminal stays between left and right panels in contentSplit.
        var insertionIndex: Int?
        if let splitParent = parentView as? NSSplitView {
            insertionIndex = splitParent.arrangedSubviews.firstIndex(of: rootView)
        }

        rootView.removeFromSuperview()

        let newRoot = buildView(from: tree, frame: frame)
        rootView = newRoot

        if let parent = parentView {
            newRoot.frame = frame
            newRoot.autoresizingMask = [.width, .height]
            if let splitParent = parent as? NSSplitView, let idx = insertionIndex {
                splitParent.insertArrangedSubview(newRoot, at: min(idx, splitParent.arrangedSubviews.count))
            } else {
                parent.addSubview(newRoot)
            }
        }
    }

    private func buildView(from node: SplitNode, frame: NSRect) -> NSView {
        switch node {
        case .pane(let id):
            guard let pane = panes[id] else {
                // Shouldn't happen, but safety fallback
                let placeholder = NSView(frame: frame)
                placeholder.wantsLayer = true
                placeholder.layer?.backgroundColor = NSColor.red.cgColor
                return placeholder
            }
            pane.terminalView.frame = frame
            return pane.terminalView

        case .split(let direction, let children, let ratios):
            let splitView = NSSplitView(frame: frame)
            splitView.isVertical = (direction == .vertical)
            splitView.dividerStyle = .thin
            splitView.autoresizingMask = [.width, .height]
            splitView.delegate = self

            for (index, child) in children.enumerated() {
                let ratio = index < ratios.count ? ratios[index] : (children.isEmpty ? 1.0 : 1.0 / CGFloat(children.count))
                let childFrame: NSRect
                if direction == .vertical {
                    let width = frame.width * ratio
                    childFrame = NSRect(x: 0, y: 0, width: width, height: frame.height)
                } else {
                    let height = frame.height * ratio
                    childFrame = NSRect(x: 0, y: 0, width: frame.width, height: height)
                }
                let childView = buildView(from: child, frame: childFrame)
                splitView.addSubview(childView)
            }

            splitView.adjustSubviews()
            return splitView
        }
    }

    // MARK: - NSSplitViewDelegate

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return max(proposedMinimumPosition, 100) // 100pt minimum pane size
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        let totalSize = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
        return min(proposedMaximumPosition, totalSize - 100)
    }
}
