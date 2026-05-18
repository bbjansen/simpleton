// Sources/Simpleton/OnboardingCoordinator.swift
import AppKit
import SwiftUI
import SimpletonCore

final class OnboardingCoordinator {

    private let sshConfigWatcher: () -> SSHConfigWatcher?
    private let panelRegistry: () -> PanelRegistry?
    private let aiConfig: () -> AIConfig
    private let bookmarkStore: () -> BookmarkStore?
    private let onAIConfigChanged: (AIConfig) -> Void

    init(
        sshConfigWatcher: @escaping () -> SSHConfigWatcher?,
        panelRegistry: @escaping () -> PanelRegistry?,
        aiConfig: @escaping () -> AIConfig,
        bookmarkStore: @escaping () -> BookmarkStore?,
        onAIConfigChanged: @escaping (AIConfig) -> Void
    ) {
        self.sshConfigWatcher = sshConfigWatcher
        self.panelRegistry = panelRegistry
        self.aiConfig = aiConfig
        self.bookmarkStore = bookmarkStore
        self.onAIConfigChanged = onAIConfigChanged
    }

    func showOnboardingIfNeeded() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let simpletonDir = appSupport.appendingPathComponent("Simpleton")
        let legacy  = simpletonDir.appendingPathComponent(".wizard-done")
        let current = simpletonDir.appendingPathComponent(".onboarding-done")
        guard !FileManager.default.fileExists(atPath: current.path),
              !FileManager.default.fileExists(atPath: legacy.path) else { return }

        let entries = sshConfigWatcher()?.concreteEntries ?? []

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self else { return }
            guard let window = NSApp.keyWindow else { return }

            let panels = self.panelRegistry()?.definitions ?? []
            let onAIConfigChanged = self.onAIConfigChanged
            let bookmarkStore = self.bookmarkStore
            let panelRegistry = self.panelRegistry

            let wizardView = OnboardingWizardView(
                allPanels: panels,
                sshEntries: entries,
                initialAIConfig: self.aiConfig(),
                onComplete: { profile, newAIConfig, bookmarks, groups in
                    window.endSheet(window.sheets.last ?? window)
                    try? panelRegistry()?.saveProfile(profile)
                    panelRegistry()?.activateProfile(profile)
                    if let newAIConfig {
                        onAIConfigChanged(newAIConfig)
                    }
                    Task {
                        for bookmark in bookmarks {
                            try? await bookmarkStore()?.add(bookmark)
                        }
                    }
                    FileManager.default.createFile(atPath: simpletonDir.appendingPathComponent(".onboarding-done").path, contents: nil)
                },
                onSkip: {
                    window.endSheet(window.sheets.last ?? window)
                    let defaultPanel: [String] = ["connections", "history", "file-browser", "environment", "processes", "ssh-tunnels"]
                    let silentProfile = PanelProfile(
                        id: PanelProfile.defaultProfileID,
                        name: "Default",
                        leftPanelIDs: defaultPanel,
                        rightPanelIDs: ["ai-chat"],
                        leftActivePanelID: "connections",
                        rightActivePanelID: "ai-chat"
                    )
                    try? panelRegistry()?.saveProfile(silentProfile)
                    panelRegistry()?.activateProfile(silentProfile)
                    FileManager.default.createFile(atPath: simpletonDir.appendingPathComponent(".onboarding-done").path, contents: nil)
                }
            )

            let sheetWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 550, height: 500),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            sheetWindow.contentView = NSHostingView(rootView: wizardView)
            window.beginSheet(sheetWindow, completionHandler: nil)
        }
    }
}
