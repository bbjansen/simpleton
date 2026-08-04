// Sources/Simpleton/BannerManager.swift
import AppKit

/// Owns the banner overlay shown inside a terminal pane when a process exits,
/// an SSH session disconnects, or an error occurs.  Extracted from PaneController
/// to keep banner-layout concerns isolated.
final class BannerManager {

    // MARK: - Callbacks

    var onReopenShell: (() -> Void)?
    var onClosePane: (() -> Void)?
    var onExplainError: (() -> Void)?
    var onReconnect: (() -> Void)?
    var onCancelReconnect: (() -> Void)?

    // MARK: - State

    /// The host view that banners are added to.
    private weak var hostView: NSView?

    /// The currently-visible banner (if any).
    private var bannerView: NSView?

    init(hostView: NSView) {
        self.hostView = hostView
    }

    // MARK: - Public API

    func showExitBanner(exitCode: Int32) {
        let isCleanExit = exitCode == 0
        let tintColor = isCleanExit ? DT.Banner.successTint : DT.Banner.errorTint
        let borderColor = isCleanExit ? DT.Banner.successBorder : DT.Banner.errorBorder
        let iconName = isCleanExit ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        let text = isCleanExit ? "Shell exited" : "Shell exited (code \(exitCode))"

        var buttons: [(String, () -> Void)] = []
        if !isCleanExit {
            buttons.append(("Explain", { [weak self] in self?.onExplainError?() }))
        }
        buttons.append(("Reopen Shell", { [weak self] in self?.onReopenShell?() }))
        buttons.append(("Close Pane", { [weak self] in self?.onClosePane?() }))

        layoutBanner(
            iconName: iconName,
            tintColor: tintColor,
            borderColor: borderColor,
            text: text,
            buttons: buttons
        )
    }

    func showDisconnectedBanner(canReconnect: Bool) {
        var buttons: [(String, () -> Void)] = []
        if canReconnect {
            buttons.append(("Reconnect", { [weak self] in self?.onReconnect?() }))
        }

        layoutBanner(
            iconName: "wifi.slash",
            tintColor: DT.Banner.warningTint,
            borderColor: DT.Banner.warningBorder,
            text: "Disconnected",
            buttons: buttons
        )
    }

    func showReconnecting(attempt: Int, delay: Double) {
        layoutBanner(
            iconName: "arrow.clockwise",
            tintColor: DT.Banner.infoTint,
            borderColor: DT.Banner.infoBorder,
            text: "Reconnecting (attempt \(attempt))...",
            buttons: [("Cancel", { [weak self] in self?.onCancelReconnect?() })]
        )
    }

    func showError(message: String) {
        layoutBanner(
            iconName: "exclamationmark.triangle.fill",
            tintColor: DT.Banner.errorTint,
            borderColor: DT.Banner.errorBorder,
            text: message,
            buttons: []
        )
    }

    func remove() {
        bannerView?.removeFromSuperview()
        bannerView = nil
    }

    // MARK: - Unified Layout

    /// Builds and displays a banner with icon, label, and an optional set of
    /// buttons laid out right-to-left from the trailing edge.
    ///
    /// Button order: the *last* element in `buttons` sits at the rightmost
    /// position (trailing = banner trailing - 14).  Each preceding button
    /// chains from there with -8pt spacing, matching the original layout.
    private func layoutBanner(
        iconName: String,
        tintColor: NSColor,
        borderColor: NSColor,
        text: String,
        buttons: [(String, () -> Void)]
    ) {
        remove()
        guard let hostView = hostView else { return }

        let banner = makeBannerContainer(in: hostView)
        banner.layer?.borderColor = borderColor.cgColor

        let icon = makeIcon(symbolName: iconName, tintColor: tintColor)
        banner.addSubview(icon)

        let label = makeLabel(text: text, color: tintColor)
        banner.addSubview(label)

        // Common constraints: icon + label on the leading side.
        var constraints: [NSLayoutConstraint] = [
            icon.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: DT.Banner.iconSize),
            icon.heightAnchor.constraint(equalToConstant: DT.Banner.iconSize),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
        ]

        // Lay buttons out right-to-left.  The last button in the array is the
        // rightmost; each earlier button chains from the one after it.
        var trailingAnchor = banner.trailingAnchor
        var trailingConstant: CGFloat = -14

        for definition in buttons.reversed() {
            let btn = CallbackButton(title: definition.0, callback: definition.1)
            btn.bezelStyle = .inline
            btn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            btn.translatesAutoresizingMaskIntoConstraints = false
            banner.addSubview(btn)

            constraints.append(btn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: trailingConstant))
            constraints.append(btn.centerYAnchor.constraint(equalTo: banner.centerYAnchor))

            trailingAnchor = btn.leadingAnchor
            trailingConstant = -8
        }

        NSLayoutConstraint.activate(constraints)

        banner.frame.origin.y = hostView.bounds.height - DT.Banner.height - DT.Banner.inset
        hostView.addSubview(banner)
        bannerView = banner
    }

    // MARK: - Factory Helpers

    private func makeBannerContainer(in hostView: NSView) -> NSVisualEffectView {
        let inset = DT.Banner.inset
        let banner = NSVisualEffectView(
            frame: NSRect(
                x: inset,
                y: 0,
                width: hostView.bounds.width - inset * 2,
                height: DT.Banner.height
            ))
        banner.material = .hudWindow
        banner.blendingMode = .behindWindow
        banner.state = .active
        banner.wantsLayer = true
        banner.layer?.cornerRadius = DT.Banner.cornerRadius
        banner.layer?.masksToBounds = true
        banner.layer?.borderWidth = DT.Banner.borderWidth
        banner.autoresizingMask = [.width, .minYMargin]
        return banner
    }

    private func makeIcon(symbolName: String, tintColor: NSColor) -> NSImageView {
        let icon = NSImageView(image: NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)!)
        icon.contentTintColor = tintColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: DT.Banner.iconSize, weight: .medium)
        return icon
    }

    private func makeLabel(text: String, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
}

// MARK: - CallbackButton

/// A thin NSButton subclass that fires a closure instead of requiring a
/// target/action pair.  Keeps banner wiring self-contained.
private final class CallbackButton: NSButton {
    private let callback: () -> Void

    init(title: String, callback: @escaping () -> Void) {
        self.callback = callback
        super.init(frame: .zero)
        self.title = title
        self.target = self
        self.action = #selector(fire)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func fire() {
        callback()
    }
}
