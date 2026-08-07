// Sources/Simpleton/TabManager.swift
import AppKit
import Combine
import Foundation

/// One tab in a window: an identity, its content view controller (which owns a split tree), and a
/// display title shown in the tab strip + window title bar.
final class TabItem: Identifiable {
    let id: UUID
    let container: TabContainerController
    var title: String

    init(id: UUID = UUID(), container: TabContainerController, title: String = "Simpleton") {
        self.id = id
        self.container = container
        self.title = title
    }
}

/// Owns the ordered list of tabs for a single window and which one is active. Replaces macOS native
/// window tabbing: instead of one NSWindow per tab, the window keeps one content host whose subview
/// is swapped to the active tab's container view. The WindowController observes this manager to
/// perform the actual view swap and to close the window when the last tab is removed.
final class TabManager: ObservableObject {

    @Published private(set) var tabs: [TabItem] = []
    @Published private(set) var activeTabID: UUID

    /// Called after `activeTabID` changes so the host window can swap in the active container's view.
    var onActivate: ((TabItem) -> Void)?
    /// Called when the last tab closes so the host window can close itself.
    var onLastTabClosed: (() -> Void)?
    /// Called when a tab's title changes so the host window can refresh its title bar if that tab is active.
    var onTitleChange: ((TabItem) -> Void)?

    /// The first tab is the container built at window init; it is always present.
    init(initial: TabContainerController, title: String = "Simpleton") {
        let item = TabItem(container: initial, title: title)
        self.tabs = [item]
        self.activeTabID = item.id
    }

    /// The active tab's container, or nil if (impossibly) there are no tabs.
    var activeContainer: TabContainerController? {
        tabs.first { $0.id == activeTabID }?.container
    }

    var activeItem: TabItem? {
        tabs.first { $0.id == activeTabID }
    }

    /// Append a tab and make it active. Returns the new tab's id.
    @discardableResult
    func add(container: TabContainerController, title: String = "Simpleton") -> UUID {
        let item = TabItem(container: container, title: title)
        tabs.append(item)
        activeTabID = item.id
        onActivate?(item)
        return item.id
    }

    /// Make the tab with `id` active (no-op if already active or unknown).
    func activate(_ id: UUID) {
        guard id != activeTabID, let item = tabs.first(where: { $0.id == id }) else { return }
        activeTabID = id
        onActivate?(item)
    }

    /// Remove the tab with `id`. If it was active, activate a neighbor (prefer the tab to the right,
    /// else the one to the left). If it was the last tab, notify the host to close the window.
    func close(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = (id == activeTabID)
        tabs.remove(at: index)

        if tabs.isEmpty {
            onLastTabClosed?()
            return
        }
        if wasActive {
            // Prefer the tab that shifted into this index (the old right neighbor); else the new last.
            let neighbor = tabs[min(index, tabs.count - 1)]
            activeTabID = neighbor.id
            onActivate?(neighbor)
        }
    }

    /// Activate the next tab (wraps around).
    func selectNext() {
        guard tabs.count > 1, let idx = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        activate(tabs[(idx + 1) % tabs.count].id)
    }

    /// Activate the previous tab (wraps around).
    func selectPrevious() {
        guard tabs.count > 1, let idx = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        activate(tabs[(idx - 1 + tabs.count) % tabs.count].id)
    }

    /// Activate the tab at a 1-based index (used by ⌘1…⌘9). No-op if out of range.
    func activate(index oneBased: Int) {
        guard oneBased >= 1, oneBased <= tabs.count else { return }
        activate(tabs[oneBased - 1].id)
    }

    /// Update a tab's title (used by the focused pane's onTitleChange). Publishes so the strip and,
    /// via `onTitleChange`, the window title refresh.
    func setTitle(_ title: String, for container: TabContainerController) {
        guard let item = tabs.first(where: { $0.container === container }) else { return }
        guard item.title != title else { return }
        item.title = title
        objectWillChange.send()
        onTitleChange?(item)
    }
}
