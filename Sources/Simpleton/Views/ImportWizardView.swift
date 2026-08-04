import SimpletonCore
// Sources/Simpleton/Views/ImportWizardView.swift
import SwiftUI

struct ImportWizardView: View {
    let entries: [SSHConfigEntry]
    let onComplete: ([Bookmark], [SmartGroup]) -> Void
    let onSkip: () -> Void

    @State private var step = 0
    @State private var selectedEntries: Set<String> = []
    @State private var suggestedGroups: [SmartGroup] = []
    @State private var acceptedGroups: Set<UUID> = []
    @State private var pinnedBookmarks: Set<UUID> = []
    @State private var bookmarks: [Bookmark] = []

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            HStack(spacing: 12) {
                ForEach(0..<4) { i in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(i <= step ? Color.accentColor : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                        Text(stepTitle(i))
                            .font(.system(size: 12, weight: i == step ? .semibold : .regular))
                            .foregroundColor(i == step ? .primary : .secondary)
                    }
                    if i < 3 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()

            Divider()

            // Content
            Group {
                switch step {
                case 0: importStep
                case 1: reviewStep
                case 2: organizeStep
                case 3: pinStep
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation buttons
            HStack {
                if step == 0 {
                    Button("Skip") { onSkip() }
                } else {
                    Button("Back") { step -= 1 }
                }
                Spacer()
                if step < 3 {
                    Button("Next") { advanceStep() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Done") { complete() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        .frame(width: 550, height: 500)
        .onAppear {
            selectedEntries = Set(entries.filter(\.isConcrete).map(\.hostAlias))
        }
    }

    // MARK: - Steps

    private var importStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Where are your connections?")
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 8) {
                ImportSourceRow(
                    icon: "doc.text",
                    title: "~/.ssh/config",
                    subtitle: "Found \(entries.filter(\.isConcrete).count) hosts",
                    isSelected: true
                )
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top)
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Review connections")
                .font(.headline)
                .padding(.horizontal)
            Text("Deselect any you don't want to import.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            List {
                ForEach(entries.filter(\.isConcrete), id: \.hostAlias) { entry in
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
                            Text(entry.hostAlias)
                                .font(.system(size: 13))
                            Text(entry.hostname ?? entry.hostAlias)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if let user = entry.user {
                            Text(user)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.top)
    }

    private var organizeStep: some View {
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
                    Text("No patterns detected")
                        .foregroundColor(.secondary)
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
                                Text(group.name)
                                    .font(.system(size: 13))
                                Text("\(group.rules.count) rule(s)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(.top)
    }

    private var pinStep: some View {
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
                            Text(bookmark.name)
                                .font(.system(size: 13))
                            Text(bookmark.host)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.top)
    }

    // MARK: - Logic

    private func advanceStep() {
        switch step {
        case 0:
            step = 1
        case 1:
            // Convert selected entries to bookmarks
            bookmarks =
                entries
                .filter { selectedEntries.contains($0.hostAlias) }
                .map { $0.toBookmark() }
            // Generate smart group suggestions
            suggestedGroups = generateSmartGroups(from: bookmarks)
            acceptedGroups = Set(suggestedGroups.map(\.id))
            step = 2
        case 2:
            step = 3
        default:
            break
        }
    }

    private func complete() {
        // Apply pins
        for i in bookmarks.indices {
            bookmarks[i].pinned = pinnedBookmarks.contains(bookmarks[i].id)
        }
        let groups = suggestedGroups.filter { acceptedGroups.contains($0.id) }
        onComplete(bookmarks, groups)
    }

    private func generateSmartGroups(from bookmarks: [Bookmark]) -> [SmartGroup] {
        var groups: [SmartGroup] = []

        // Group by hostname patterns
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

        // Group by jump host
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

    private func stepTitle(_ index: Int) -> String {
        switch index {
        case 0: return "Import"
        case 1: return "Review"
        case 2: return "Organize"
        case 3: return "Pin"
        default: return ""
        }
    }
}

struct ImportSourceRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 18))
                .frame(width: 30)
            VStack(alignment: .leading) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(12)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.white.opacity(0.04))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear))
    }
}
