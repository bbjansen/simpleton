// Sources/Simpleton/Views/ScrollbackSearchBar.swift
import AppKit
import SwiftTerm

/// Inline search bar for scrollback search (Cmd+F).
/// Placed at the top of a TerminalView.
final class ScrollbackSearchBar: NSView {

    private let searchField: NSSearchField
    private let prevButton: NSButton
    private let nextButton: NSButton
    private let closeButton: NSButton
    private let matchLabel: NSTextField
    private weak var terminalView: TerminalView?

    var onDismiss: (() -> Void)?

    init(terminalView: TerminalView) {
        self.terminalView = terminalView

        searchField = NSSearchField(frame: .zero)
        searchField.placeholderString = "Search scrollback..."
        searchField.font = NSFont.systemFont(ofSize: 12)

        prevButton = NSButton(title: "◀", target: nil, action: nil)
        prevButton.bezelStyle = .inline
        prevButton.font = NSFont.systemFont(ofSize: 11)

        nextButton = NSButton(title: "▶", target: nil, action: nil)
        nextButton.bezelStyle = .inline
        nextButton.font = NSFont.systemFont(ofSize: 11)

        closeButton = NSButton(title: "✕", target: nil, action: nil)
        closeButton.bezelStyle = .inline
        closeButton.font = NSFont.systemFont(ofSize: 11)

        matchLabel = NSTextField(labelWithString: "")
        matchLabel.font = NSFont.systemFont(ofSize: 11)
        matchLabel.textColor = .secondaryLabelColor

        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 32))

        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.95).cgColor

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
            heightAnchor.constraint(equalToConstant: 32),

            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            searchField.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),

            prevButton.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 4),
            prevButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            nextButton.leadingAnchor.constraint(equalTo: prevButton.trailingAnchor, constant: 2),
            nextButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            matchLabel.leadingAnchor.constraint(equalTo: nextButton.trailingAnchor, constant: 8),
            matchLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
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
