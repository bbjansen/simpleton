// Sources/Simpleton/SSHConfigWatcher.swift
import Foundation
import SimpletonCore

/// Watches ~/.ssh/config for changes and re-parses on modification.
final class SSHConfigWatcher {

    /// Called on the main queue when the parsed SSH config entries change.
    var onConfigChanged: (([SSHConfigEntry]) -> Void)?

    private var stream: FSEventStreamRef?
    private let configPath: String
    private var lastEntries: [SSHConfigEntry] = []

    init(configPath: String = "~/.ssh/config") {
        self.configPath = NSString(string: configPath).expandingTildeInPath
    }

    deinit {
        stop()
    }

    /// Start watching. Performs an initial parse immediately.
    func start() {
        // Initial parse
        reparseAndNotify()

        // Watch the .ssh directory (FSEvents watches directories, not files)
        let sshDir = (configPath as NSString).deletingLastPathComponent
        guard FileManager.default.fileExists(atPath: sshDir) else { return }

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let pathsToWatch = [sshDir] as CFArray
        stream = FSEventStreamCreate(
            nil,
            { (_, clientCallBackInfo, _, _, _, _) in
                guard let info = clientCallBackInfo else { return }
                let watcher = Unmanaged<SSHConfigWatcher>.fromOpaque(info).takeUnretainedValue()
                DispatchQueue.main.async {
                    watcher.reparseAndNotify()
                }
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,  // 1 second latency (batches rapid changes)
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )

        guard let stream = stream else { return }
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
    }

    /// Stop watching.
    func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// Parse the current config and notify if entries changed.
    private func reparseAndNotify() {
        let entries = SSHConfigParser.parseFile(at: configPath)
        if entries != lastEntries {
            lastEntries = entries
            onConfigChanged?(entries)
        }
    }

    /// Get current parsed entries without waiting for a change.
    var currentEntries: [SSHConfigEntry] {
        lastEntries
    }

    /// Get only concrete (non-wildcard) entries.
    var concreteEntries: [SSHConfigEntry] {
        lastEntries.filter(\.isConcrete)
    }
}
