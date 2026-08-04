// Sources/Simpleton/Plugins/ThemeDiscovery.swift
import Foundation
import SimpletonCore

/// Discovers and watches JSON theme files in the themes directory.
final class ThemeDiscovery {

    private let directory: URL
    private var stream: FSEventStreamRef?
    private(set) var themes: [Theme] = []

    /// Called when the theme list changes.
    var onThemesChanged: (([Theme]) -> Void)?

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        stop()
    }

    /// Start watching and perform initial scan.
    func start() {
        rescan()
        startWatching()
    }

    func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// Get a theme by name. Returns nil if not found.
    func theme(named name: String) -> Theme? {
        themes.first { $0.name == name }
    }

    /// All theme names.
    var themeNames: [String] {
        themes.map(\.name).sorted()
    }

    // MARK: - Private

    private func rescan() {
        var discovered: [Theme] = []

        // Built-in themes
        discovered.append(Theme(name: "Simpleton Dark"))
        discovered.append(
            Theme(
                name: "Simpleton Light",
                colors: ThemeColors(
                    background: "#f8fafc", foreground: "#1a1a2e",
                    cursor: "#818cf8", selection: "#c7d2fe",
                    black: "#1a1a2e", red: "#dc2626",
                    green: "#16a34a", yellow: "#ca8a04",
                    blue: "#2563eb", magenta: "#9333ea",
                    cyan: "#0891b2", white: "#f8fafc",
                    brightBlack: "#64748b", brightRed: "#ef4444",
                    brightGreen: "#22c55e", brightYellow: "#eab308",
                    brightBlue: "#3b82f6", brightMagenta: "#a855f7",
                    brightCyan: "#06b6d4", brightWhite: "#ffffff",
                    splitBorder: "#e2e8f0", sidebar: "#f1f5f9",
                    tabBar: "#e2e8f0"
                )))

        // User themes from directory
        if let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "json" {
                if let data = try? Data(contentsOf: file),
                    let themeFile = try? JSONDecoder().decode(ThemeFile.self, from: data)
                {
                    discovered.append(themeFile.theme)
                }
            }
        }

        themes = discovered
        onThemesChanged?(themes)
    }

    private func startWatching() {
        let path = directory.path
        guard FileManager.default.fileExists(atPath: path) else { return }

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        stream = FSEventStreamCreate(
            nil,
            { (_, info, _, _, _, _) in
                guard let info = info else { return }
                let discovery = Unmanaged<ThemeDiscovery>.fromOpaque(info).takeUnretainedValue()
                DispatchQueue.main.async { discovery.rescan() }
            },
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )

        guard let stream = stream else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }
}
