// Sources/Simpleton/Views/ScrollbackSearchBar.swift
import AppKit
import SwiftTerm

/// Inline search bar for scrollback search (Cmd+F).
/// Placed at the top of a TerminalView with premium dark glassmorphism style.
final class ScrollbackSearchBar: NSVisualEffectView {

    private let searchField: NSTextField
    private let prevButton: NSButton
    private let nextButton: NSButton
    private let closeButton: NSButton
    private let matchLabel: NSTextField
    private weak var terminalView: TerminalView?

    var onDismiss: (() -> Void)?

    init(terminalView: TerminalView) {
        self.terminalView = terminalView

        // Search field — custom styled, larger text
        searchField = NSTextField(frame: .zero)
        searchField.placeholderString = "Search scrollback..."
        searchField.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        searchField.isBordered = false
        searchField.drawsBackground = true
        searchField.backgroundColor = NSColor(red: 0.082, green: 0.082, blue: 0.122, alpha: 1)  // Theme.elevated
        searchField.textColor = .white
        searchField.focusRingType = .exterior
        searchField.wantsLayer = true
        searchField.layer?.cornerRadius = 6
        searchField.layer?.borderWidth = 1
        searchField.layer?.borderColor = NSColor(red: 0.165, green: 0.165, blue: 0.227, alpha: 1).cgColor

        // Nav buttons — SF Symbol icons in small circular style
        let prevImage = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Previous match")!
        prevButton = NSButton(image: prevImage, target: nil, action: nil)
        prevButton.bezelStyle = .circular
        prevButton.isBordered = false
        prevButton.contentTintColor = .white
        prevButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)

        let nextImage = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Next match")!
        nextButton = NSButton(image: nextImage, target: nil, action: nil)
        nextButton.bezelStyle = .circular
        nextButton.isBordered = false
        nextButton.contentTintColor = .white
        nextButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)

        let closeImage = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close search")!
        closeButton = NSButton(image: closeImage, target: nil, action: nil)
        closeButton.bezelStyle = .circular
        closeButton.isBordered = false
        closeButton.contentTintColor = NSColor(white: 0.5, alpha: 1)
        closeButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)

        matchLabel = NSTextField(labelWithString: "")
        matchLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        matchLabel.textColor = NSColor(red: 0.353, green: 0.353, blue: 0.416, alpha: 1)  // Theme.textTertiary

        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 36))

        // Glassmorphism backing
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor(red: 0.165, green: 0.165, blue: 0.227, alpha: 1).cgColor

        addSubview(searchField)
        addSubview(prevButton)
        addSubview(nextButton)
        addSubview(matchLabel)
        addSubview(closeButton)

        searchField.target = self
        searchField.action = #selector(searchChanged)
        prevButton.target = self
        prevButton.action = #selector(findPreviousMatch)
        nextButton.target = self
        nextButton.action = #selector(findNextMatch)
        closeButton.target = self
        closeButton.action = #selector(dismiss)

        setupLayout()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupLayout() {
        searchField.translatesAutoresizingMaskIntoConstraints = false
        prevButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        matchLabel.translatesAutoresizingMaskIntoConstraints = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 36),

            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            searchField.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            searchField.heightAnchor.constraint(equalToConstant: 24),

            prevButton.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 6),
            prevButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            prevButton.widthAnchor.constraint(equalToConstant: 22),
            prevButton.heightAnchor.constraint(equalToConstant: 22),

            nextButton.leadingAnchor.constraint(equalTo: prevButton.trailingAnchor, constant: 2),
            nextButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 22),
            nextButton.heightAnchor.constraint(equalToConstant: 22),

            matchLabel.leadingAnchor.constraint(equalTo: nextButton.trailingAnchor, constant: 8),
            matchLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 22),
            closeButton.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    func activate() {
        window?.makeFirstResponder(searchField)
    }

    @objc private func searchChanged() {
        guard let text = searchField.stringValue.isEmpty ? nil : searchField.stringValue else {
            matchLabel.stringValue = ""
            terminalView?.clearSearch()
            return
        }
        let found = terminalView?.findNext(text) ?? false
        matchLabel.stringValue = found ? "Match found" : "No matches"
    }

    @objc private func findNextMatch() {
        guard let text = searchField.stringValue.isEmpty ? nil : searchField.stringValue else { return }
        let found = terminalView?.findNext(text) ?? false
        matchLabel.stringValue = found ? "Match found" : "No matches"
    }

    @objc private func findPreviousMatch() {
        guard let text = searchField.stringValue.isEmpty ? nil : searchField.stringValue else { return }
        let found = terminalView?.findPrevious(text) ?? false
        matchLabel.stringValue = found ? "Match found" : "No matches"
    }

    @objc private func dismiss() {
        terminalView?.clearSearch()
        onDismiss?()
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }
}
