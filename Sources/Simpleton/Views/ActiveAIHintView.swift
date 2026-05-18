// Sources/Simpleton/Views/ActiveAIHintView.swift
import AppKit

/// A non-intrusive toast overlay shown at the bottom of a terminal pane when
/// a command fails.  Displays an AI-generated error hint with dismiss and
/// "Ask AI" actions.  Auto-dismisses after 8 seconds.
final class ActiveAIHintView: NSVisualEffectView {

    // MARK: - Callbacks

    var onDismiss: (() -> Void)?
    var onAskAI: (() -> Void)?

    // MARK: - State

    private var autoDismissTimer: Timer?

    // MARK: - Init

    init(hint: String, hostBounds: NSRect) {
        let inset: CGFloat = DT.Banner.inset
        let height: CGFloat = 36
        let frame = NSRect(
            x: inset,
            y: inset,
            width: hostBounds.width - inset * 2,
            height: height
        )
        super.init(frame: frame)
        setup(hint: hint)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        autoDismissTimer?.invalidate()
    }

    // MARK: - Layout

    private func setup(hint: String) {
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = DT.Banner.cornerRadius
        layer?.masksToBounds = true
        layer?.borderWidth = DT.Banner.borderWidth
        layer?.borderColor = DT.Banner.infoBorder.cgColor
        autoresizingMask = [.width, .maxYMargin]

        // Icon
        let icon = NSImageView(
            image: NSImage(systemSymbolName: "sparkles", accessibilityDescription: "AI hint")!
        )
        icon.contentTintColor = DT.Banner.infoTint
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: DT.Banner.iconSize, weight: .medium
        )
        addSubview(icon)

        // Label
        let label = NSTextField(labelWithString: hint)
        label.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        label.textColor = DT.Banner.infoTint
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)

        // Ask AI button
        let askButton = HintButton(title: "Ask AI") { [weak self] in
            self?.onAskAI?()
            self?.dismiss()
        }
        addSubview(askButton)

        // Dismiss button
        let dismissButton = HintButton(title: "Dismiss") { [weak self] in
            self?.dismiss()
        }
        addSubview(dismissButton)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: DT.Banner.iconSize),
            icon.heightAnchor.constraint(equalToConstant: DT.Banner.iconSize),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: askButton.leadingAnchor, constant: -8),

            dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            dismissButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            askButton.trailingAnchor.constraint(equalTo: dismissButton.leadingAnchor, constant: -6),
            askButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // Auto-dismiss after 8 seconds.
        autoDismissTimer = Timer.scheduledTimer(
            withTimeInterval: 8, repeats: false
        ) { [weak self] _ in
            self?.dismiss()
        }
    }

    // MARK: - Dismiss

    private func dismiss() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.onDismiss?()
            self?.removeFromSuperview()
        })
    }
}

// MARK: - HintButton

/// Minimal inline button used inside the hint toast.
private final class HintButton: NSButton {

    private let callback: () -> Void

    init(title: String, callback: @escaping () -> Void) {
        self.callback = callback
        super.init(frame: .zero)
        self.title = title
        self.bezelStyle = .inline
        self.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.target = self
        self.action = #selector(fire)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func fire() {
        callback()
    }
}
