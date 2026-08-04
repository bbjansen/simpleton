import SimpletonCore
// Sources/Simpleton/Views/OnboardingWizardView.swift
import SwiftUI

struct OnboardingWizardView: View {
    let allPanels: [PanelDefinition]
    let sshEntries: [SSHConfigEntry]
    let initialAIConfig: AIConfig
    let onComplete: (PanelProfile, AIConfig?, [Bookmark], [SmartGroup]) -> Void
    let onSkip: () -> Void

    @ObservedObject private var themeSettings = ThemeSettings.shared

    // Navigation
    @State private var step = 0

    // Step 1: panel toggles
    @State private var enabledPanels: [String: Bool]

    // Step 2: AI config
    @State private var aiConfig: AIConfig
    @State private var aiConfigured = false

    // SSH steps (reused from ImportWizardView)
    @State private var selectedEntries: Set<String> = []
    @State private var bookmarks: [Bookmark] = []
    @State private var suggestedGroups: [SmartGroup] = []
    @State private var acceptedGroups: Set<UUID> = []
    @State private var pinnedBookmarks: Set<UUID> = []

    private var hasSSSHConfig: Bool { !sshEntries.isEmpty }
    // Steps: 0=welcome, 1=panels, 2=ai, 3-6=ssh (if applicable), last=done
    private var doneStep: Int { hasSSSHConfig ? 7 : 3 }

    init(
        allPanels: [PanelDefinition],
        sshEntries: [SSHConfigEntry],
        initialAIConfig: AIConfig,
        onComplete: @escaping (PanelProfile, AIConfig?, [Bookmark], [SmartGroup]) -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.allPanels = allPanels
        self.sshEntries = sshEntries
        self.initialAIConfig = initialAIConfig
        self.onComplete = onComplete
        self.onSkip = onSkip
        _aiConfig = State(initialValue: initialAIConfig)

        let defaultOff: Set<String> = [
            PanelProfile.PanelID.git,
            PanelProfile.PanelID.docker,
            PanelProfile.PanelID.skills,
        ]
        var defaults: [String: Bool] = [:]
        for panel in allPanels {
            defaults[panel.id] = !defaultOff.contains(panel.id)
        }
        _enabledPanels = State(initialValue: defaults)
    }

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
            Divider()
            Group {
                switch step {
                case 0: welcomeStep
                case 1: panelsStep
                case 2: aiStep
                case 3 where hasSSSHConfig: sshImportStep
                case 4 where hasSSSHConfig: sshReviewStep
                case 5 where hasSSSHConfig: sshOrganizeStep
                case 6 where hasSSSHConfig: sshPinStep
                default: completionStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 550, height: 500)
        .onAppear {
            selectedEntries = Set(sshEntries.filter(\.isConcrete).map(\.hostAlias))
        }
    }

    // MARK: - Step indicator

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            let total = doneStep + 1
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i == step ? themeSettings.accent : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "terminal.fill")
                .font(.system(size: 48))
                .foregroundStyle(themeSettings.accent)
            Text("Welcome to Simpleton")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("A fast, native macOS terminal.\nLet's set up your workspace.")
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            HStack {
                Button("Skip setup") { completeWithDefaults() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.secondary)
                Spacer()
                Button("Get started") { step = 1 }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .padding()
    }

    // MARK: - Step 1: Panels

    private var panelsStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("Choose your panels")
                    .font(.title2).fontWeight(.semibold)
                Text("You can change these any time in Preferences → Profiles")
                    .font(.subheadline).foregroundStyle(Color.secondary)
            }
            .padding()
            Divider()
            List {
                ForEach(allPanels, id: \.id) { panel in
                    Toggle(
                        isOn: Binding(
                            get: { enabledPanels[panel.id] ?? false },
                            set: { enabledPanels[panel.id] = $0 }
                        )
                    ) {
                        HStack(spacing: 10) {
                            Image(systemName: panel.icon)
                                .frame(width: 20)
                                .foregroundStyle(themeSettings.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(panel.name)
                                Text(panel.description)
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                                if panel.id == PanelProfile.PanelID.skills {
                                    Text("Requires AI configuration")
                                        .font(.caption2)
                                        .foregroundStyle(Color.orange)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            Divider()
            HStack {
                Button("Back") { step = 0 }
                    .buttonStyle(.plain).foregroundStyle(Color.secondary)
                Spacer()
                Button("Next") { step = 2 }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
    }

    // MARK: - Step 2: AI

    private var aiStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("Set up AI (optional)")
                    .font(.title2).fontWeight(.semibold)
                Text("Powers the AI Chat panel and Skills")
                    .font(.subheadline).foregroundStyle(Color.secondary)
            }
            .padding()
            Divider()
            AIPreferencesTab(config: aiConfig) { newConfig in
                aiConfig = newConfig
                aiConfigured = newConfig.enabled
            }
            Divider()
            HStack {
                Button("Back") { step = 1 }
                    .buttonStyle(.plain).foregroundStyle(Color.secondary)
                Spacer()
                Button("Skip for now") { advanceFromAI() }
                    .buttonStyle(.plain).foregroundStyle(Color.secondary)
                Button("Next") { advanceFromAI() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
    }

    // MARK: - SSH steps (verbatim from ImportWizardView)

    private var sshImportStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Where are your connections?")
                .font(.headline)
                .padding(.horizontal)
            VStack(spacing: 8) {
                ImportSourceRow(
                    icon: "doc.text",
                    title: "~/.ssh/config",
                    subtitle: "Found \(sshEntries.filter(\.isConcrete).count) hosts",
                    isSelected: true
                )
            }
            .padding(.horizontal)
            Spacer()
            HStack {
                Button("Back") { step = 2 }
                    .buttonStyle(.plain).foregroundStyle(Color.secondary)
                Spacer()
                Button("Next") { advanceSSHStep() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .padding(.top)
    }

    private var sshReviewStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Review connections")
                .font(.headline)
                .padding(.horizontal)
            Text("Deselect any you don't want to import.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            List {
                ForEach(sshEntries.filter(\.isConcrete), id: \.hostAlias) { entry in
                    HStack {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { selectedEntries.contains(entry.hostAlias) },
                                set: {
                                    if $0 {
                                        selectedEntries.insert(entry.hostAlias)
                                    } else {
                                        selectedEntries.remove(entry.hostAlias)
                                    }
                                }
                            )
                        )
                        .labelsHidden()
                        VStack(alignment: .leading) {
                            Text(entry.hostAlias).font(.system(size: 13))
                            Text(entry.hostname ?? entry.hostAlias)
                                .font(.system(size: 11)).foregroundColor(.secondary)
                        }
                        Spacer()
                        if let user = entry.user {
                            Text(user).font(.system(size: 11)).foregroundColor(.secondary)
                        }
                    }
                }
            }
            HStack {
                Button("Back") { step -= 1 }
                    .buttonStyle(.plain).foregroundStyle(Color.secondary)
                Spacer()
                Button("Next") { advanceSSHStep() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .padding(.top)
    }

    private var sshOrganizeStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested smart groups")
                .font(.headline)
                .padding(.horizontal)
            Text("Accept or skip each suggestion.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            if suggestedGroups.isEmpty {
                VStack {
                    Spacer()
                    Text("No patterns detected").foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(suggestedGroups) { group in
                        HStack {
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { acceptedGroups.contains(group.id) },
                                    set: {
                                        if $0 {
                                            acceptedGroups.insert(group.id)
                                        } else {
                                            acceptedGroups.remove(group.id)
                                        }
                                    }
                                )
                            )
                            .labelsHidden()
                            Circle()
                                .fill(Color(hex: group.color) ?? .gray)
                                .frame(width: 10, height: 10)
                            VStack(alignment: .leading) {
                                Text(group.name).font(.system(size: 13))
                                Text("\(group.rules.count) rule(s)")
                                    .font(.system(size: 11)).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            HStack {
                Button("Back") { step -= 1 }
                    .buttonStyle(.plain).foregroundStyle(Color.secondary)
                Spacer()
                Button("Next") { step += 1 }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .padding(.top)
    }

    private var sshPinStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pin your daily drivers")
                .font(.headline)
                .padding(.horizontal)
            Text("These will always be visible at the top of the sidebar.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            List {
                ForEach(bookmarks) { bookmark in
                    HStack {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { pinnedBookmarks.contains(bookmark.id) },
                                set: {
                                    if $0 {
                                        pinnedBookmarks.insert(bookmark.id)
                                    } else {
                                        pinnedBookmarks.remove(bookmark.id)
                                    }
                                }
                            )
                        )
                        .labelsHidden()
                        Image(systemName: pinnedBookmarks.contains(bookmark.id) ? "star.fill" : "star")
                            .foregroundColor(pinnedBookmarks.contains(bookmark.id) ? .yellow : .secondary)
                            .font(.system(size: 12))
                        VStack(alignment: .leading) {
                            Text(bookmark.name).font(.system(size: 13))
                            Text(bookmark.host).font(.system(size: 11)).foregroundColor(.secondary)
                        }
                    }
                }
            }
            HStack {
                Button("Back") { step -= 1 }
                    .buttonStyle(.plain).foregroundStyle(Color.secondary)
                Spacer()
                Button("Done") { finish() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .padding(.top)
    }

    // MARK: - Completion step

    private var completionStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.green)
            Text("You're all set!")
                .font(.largeTitle).fontWeight(.bold)
            VStack(alignment: .leading, spacing: 4) {
                let panelCount = enabledPanels.filter { $0.value }.count
                Text("• \(panelCount) panels enabled")
                if aiConfigured { Text("• AI assistant configured") }
                if !bookmarks.isEmpty { Text("• \(bookmarks.count) connections imported") }
            }
            .font(.subheadline)
            .foregroundStyle(Color.secondary)
            Spacer()
            Button("Start using Simpleton") { finish() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .padding()
        }
    }

    // MARK: - Navigation

    private func advanceFromAI() {
        step = hasSSSHConfig ? 3 : doneStep
    }

    private func advanceSSHStep() {
        // Only generate bookmarks/groups on first entry into step 4. Re-entering
        // (Review → Organize → Back → Next) must preserve the user's group choices
        // instead of resetting acceptedGroups back to all-selected.
        if step == 4 && bookmarks.isEmpty {
            bookmarks =
                sshEntries
                .filter { selectedEntries.contains($0.hostAlias) }
                .map { $0.toBookmark() }
            suggestedGroups = generateSmartGroups(from: bookmarks)
            acceptedGroups = Set(suggestedGroups.map(\.id))
        }
        step += 1
    }

    private func finish() {
        let profile = buildProfile()
        let finalAI = aiConfigured ? aiConfig : nil
        for i in bookmarks.indices {
            bookmarks[i].pinned = pinnedBookmarks.contains(bookmarks[i].id)
        }
        let finalGroups = suggestedGroups.filter { acceptedGroups.contains($0.id) }
        onComplete(profile, finalAI, bookmarks, finalGroups)
    }

    private func completeWithDefaults() {
        onSkip()
    }

    private func buildProfile() -> PanelProfile {
        let leftIDs =
            allPanels
            .filter { ($0.defaultSide == .left) && (enabledPanels[$0.id] ?? false) }
            .map(\.id)
        let rightIDs =
            allPanels
            .filter { ($0.defaultSide == .right) && (enabledPanels[$0.id] ?? false) }
            .map(\.id)
        return PanelProfile(
            id: PanelProfile.defaultProfileID,
            name: "Default",
            leftPanelIDs: leftIDs,
            rightPanelIDs: rightIDs,
            leftActivePanelID: leftIDs.first,
            rightActivePanelID: rightIDs.first
        )
    }

    private func generateSmartGroups(from bookmarks: [Bookmark]) -> [SmartGroup] {
        var groups: [SmartGroup] = []
        let prodHosts = bookmarks.filter { $0.host.contains("prod") || $0.name.contains("prod") }
        if prodHosts.count >= 2 {
            groups.append(
                SmartGroup(
                    name: "Production",
                    color: "#ef4444",
                    combinator: .or,
                    rules: [SmartGroupRule(field: .hostname, operator: .contains, value: "prod")]
                ))
        }
        let stagingHosts = bookmarks.filter { $0.host.contains("staging") || $0.name.contains("staging") }
        if stagingHosts.count >= 2 {
            groups.append(
                SmartGroup(
                    name: "Staging",
                    color: "#eab308",
                    combinator: .or,
                    rules: [SmartGroupRule(field: .hostname, operator: .contains, value: "staging")]
                ))
        }
        let jumpHostGroups = Dictionary(grouping: bookmarks.filter { !$0.jumpHosts.isEmpty }) {
            $0.jumpHosts.first ?? ""
        }
        for (jumpHost, hosts) in jumpHostGroups where hosts.count >= 2 {
            groups.append(
                SmartGroup(
                    name: "Via \(jumpHost)",
                    color: "#818cf8",
                    combinator: .and,
                    rules: [SmartGroupRule(field: .jumpHost, operator: .equals, value: jumpHost)]
                ))
        }
        return groups
    }
}
