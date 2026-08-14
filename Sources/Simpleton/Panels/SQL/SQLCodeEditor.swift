// Sources/Simpleton/Panels/SQL/SQLCodeEditor.swift
import AppKit
import SimpletonSQL
import SwiftUI

/// A real SQL editor: an `NSTextView` (wrapped for SwiftUI) with tokenizer-driven syntax
/// highlighting, line numbers (a ruler), schema-aware autocomplete, and ⌘↵ (run) / ⌘⇧↵ (run
/// selection or current statement). Hand-rolled — no dependencies. The pure classification lives in
/// `SQLTokenizer` (SimpletonSQL); this applies themed colors and wires the interactions.
struct SQLCodeEditor: NSViewRepresentable {
    @Binding var text: String
    /// Completion candidates from the live schema: table names + column names.
    let tableNames: [String]
    let columnNames: [String]
    let font: NSFont
    var onRun: () -> Void
    var onRunSelection: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let textView = SQLTextView()
        textView.coordinator = context.coordinator
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.font = font
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        textView.textStorage?.delegate = context.coordinator

        scroll.documentView = textView
        scroll.hasVerticalRuler = true
        let ruler = SQLLineNumberRuler(scrollView: scroll, orientation: .verticalRuler)
        ruler.clientView = textView
        scroll.verticalRulerView = ruler
        scroll.rulersVisible = true

        context.coordinator.textView = textView
        context.coordinator.ruler = ruler
        context.coordinator.highlight()
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            textView.string = text
            context.coordinator.highlight()
        }
        if textView.font != font {
            textView.font = font
            context.coordinator.highlight()
        }
        context.coordinator.ruler?.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: SQLCodeEditor
        weak var textView: SQLTextView?
        weak var ruler: SQLLineNumberRuler?
        private var isHighlighting = false

        init(_ parent: SQLCodeEditor) { self.parent = parent }

        // MARK: text sync + autocomplete
        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            if parent.text != tv.string { parent.text = tv.string }
            ruler?.needsDisplay = true
        }

        // MARK: highlighting
        func textStorage(
            _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange, changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters) else { return }
            // Re-highlight on the next runloop tick so we never mutate attributes inside the edit
            // callback (avoids reentrancy); queries are small so a full re-highlight is cheap.
            DispatchQueue.main.async { [weak self] in self?.highlight() }
        }

        func highlight() {
            guard !isHighlighting, let tv = textView, let storage = tv.textStorage else { return }
            isHighlighting = true
            defer { isHighlighting = false }
            let full = NSRange(location: 0, length: (tv.string as NSString).length)
            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: DT.Grid.rowText, range: full)
            storage.addAttribute(.font, value: parent.font, range: full)
            for token in SQLTokenizer.tokens(in: tv.string) {
                let range = NSRange(location: token.location, length: token.length)
                guard range.location + range.length <= full.length else { continue }
                storage.addAttribute(.foregroundColor, value: Self.color(for: token.kind), range: range)
            }
            storage.endEditing()
        }

        static func color(for kind: SQLTokenKind) -> NSColor {
            switch kind {
            case .keyword: return AppTheme.accentNSColor
            case .string: return DT.Banner.successTint
            case .comment: return DT.Grid.nullText
            case .number: return DT.Banner.warningTint
            case .identifier: return DT.Grid.rowText
            }
        }

        // MARK: completions
        func textView(
            _ textView: NSTextView, completions words: [String],
            forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>?
        ) -> [String] {
            let ns = textView.string as NSString
            guard charRange.location + charRange.length <= ns.length else { return [] }
            let prefix = ns.substring(with: charRange).lowercased()
            guard !prefix.isEmpty else { return [] }
            // Columns first (most specific), then tables, then keywords — de-duplicated, prefix match.
            var seen = Set<String>()
            var out: [String] = []
            func add(_ candidates: [String]) {
                for c in candidates where c.lowercased().hasPrefix(prefix) {
                    let key = c.lowercased()
                    if seen.insert(key).inserted { out.append(c) }
                }
            }
            add(parent.columnNames)
            add(parent.tableNames)
            add(SQLTokenizer.keywords.sorted())
            return out
        }
    }
}

/// The `NSTextView` subclass: intercepts ⌘↵ / ⌘⇧↵ and triggers completion on word characters.
final class SQLTextView: NSTextView {
    weak var coordinator: SQLCodeEditor.Coordinator?

    override func keyDown(with event: NSEvent) {
        // Return (keyCode 36) with Command runs; with Shift+Command runs the selection / current line.
        if event.keyCode == 36, event.modifierFlags.contains(.command) {
            if event.modifierFlags.contains(.shift) {
                coordinator?.parent.onRunSelection(currentStatementText())
            } else {
                coordinator?.parent.onRun()
            }
            return
        }
        super.keyDown(with: event)
        // Offer completions while typing an identifier (debounced by AppKit's own coalescing).
        if let chars = event.characters, chars.count == 1,
            let scalar = chars.unicodeScalars.first,
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
        {
            complete(nil)
        }
    }

    /// The selected text, or — when the selection is empty — the statement around the caret (split on
    /// `;`), so ⌘⇧↵ runs "the statement I'm in".
    private func currentStatementText() -> String {
        let ns = string as NSString
        let sel = selectedRange()
        if sel.length > 0 { return ns.substring(with: sel) }
        // Empty selection: expand to the `;`-delimited statement containing the caret.
        let caret = sel.location
        var start = caret
        while start > 0, ns.character(at: start - 1) != UInt16(UnicodeScalar(";").value) { start -= 1 }
        var end = caret
        while end < ns.length, ns.character(at: end) != UInt16(UnicodeScalar(";").value) { end += 1 }
        return ns.substring(with: NSRange(location: start, length: end - start))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A ruler that draws right-aligned line numbers next to the text.
final class SQLLineNumberRuler: NSRulerView {
    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = clientView as? NSTextView,
            let layoutManager = textView.layoutManager,
            let container = textView.textContainer
        else { return }
        let ns = textView.string as NSString
        let visible = textView.visibleRect
        let inset = textView.textContainerInset.height
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: DT.Grid.nullText,
        ]

        // Walk line fragments; number a line when the fragment starts a new paragraph.
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        var lineNumber = lineIndex(upTo: layoutManager.characterIndexForGlyph(at: glyphRange.location), in: ns) + 1
        var index = glyphRange.location
        var lastParagraphStart = -1
        while index < NSMaxRange(glyphRange) {
            let charIndex = layoutManager.characterIndexForGlyph(at: index)
            let paraRange = ns.paragraphRange(for: NSRange(location: charIndex, length: 0))
            if paraRange.location != lastParagraphStart {
                lastParagraphStart = paraRange.location
                var effective = NSRange()
                let fragRect = layoutManager.lineFragmentRect(forGlyphAt: index, effectiveRange: &effective)
                let y = fragRect.minY + inset - visible.minY
                let label = "\(lineNumber)" as NSString
                let size = label.size(withAttributes: attrs)
                label.draw(
                    at: NSPoint(x: ruleThickness - size.width - 4, y: y + (fragRect.height - size.height) / 2),
                    withAttributes: attrs)
                lineNumber += 1
                index = NSMaxRange(effective)
            } else {
                var effective = NSRange()
                _ = layoutManager.lineFragmentRect(forGlyphAt: index, effectiveRange: &effective)
                index = NSMaxRange(effective)
            }
        }
        ruleThickness = 34
    }

    private func lineIndex(upTo charIndex: Int, in ns: NSString) -> Int {
        var count = 0
        var i = 0
        while i < charIndex, i < ns.length {
            if ns.character(at: i) == UInt16(UnicodeScalar("\n").value) { count += 1 }
            i += 1
        }
        return count
    }
}
