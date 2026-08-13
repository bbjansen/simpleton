// Sources/Simpleton/TerminalDropTarget.swift
import AppKit
import SwiftTerm

/// Transparent overlay that accepts file URL drags and sends quoted paths
/// into the terminal. Returns nil from hitTest so mouse events pass through.
final class TerminalDropTarget: NSView {
    weak var targetTerminal: LocalProcessTerminalView?

    init(terminal: LocalProcessTerminalView) {
        self.targetTerminal = terminal
        super.init(frame: terminal.bounds)
        autoresizingMask = [.width, .height]
        registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType("com.simpleton.connection-id")])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        // A data-connection drag → open a text (CLI) client pane for that connection.
        let connType = NSPasteboard.PasteboardType("com.simpleton.connection-id")
        if let idString = sender.draggingPasteboard.string(forType: connType),
            let id = UUID(uuidString: idString)
        {
            NotificationCenter.default.post(name: .simpletonOpenConnectionText, object: id)
            return true
        }
        guard let items = sender.draggingPasteboard.pasteboardItems else { return false }
        let paths = items.compactMap { item -> String? in
            guard let urlString = item.string(forType: .fileURL),
                let url = URL(string: urlString)
            else { return nil }
            let escaped = url.path.replacingOccurrences(of: "'", with: "'\\''")
            return "'\(escaped)'"
        }
        guard !paths.isEmpty else { return false }
        let text = paths.joined(separator: " ")
        let bytes = Array(text.utf8)
        targetTerminal?.send(data: bytes[...])
        return true
    }
}
