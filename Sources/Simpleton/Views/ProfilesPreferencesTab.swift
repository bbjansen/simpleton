import SimpletonCore
// Sources/Simpleton/Views/ProfilesPreferencesTab.swift
import SwiftUI

struct ProfilesPreferencesTab: View {
    @ObservedObject var registry: PanelRegistry
    @ObservedObject private var themeSettings = ThemeSettings.shared
    @State private var selectedProfileID: UUID?
    @State private var editingProfile: PanelProfile?
    @State private var showingTemplatePicker = false

    var body: some View {
        HSplitView {
            // Left: profile list
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(registry.profiles) { profile in
                            profileRow(profile)
                        }
                    }
                    .padding(6)
                }
                Divider()
                HStack {
                    Button(action: addProfile) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("New")
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(8)
            }
            .frame(width: 180)

            // Right: editor
            Group {
                if let profile = editingProfile {
                    ProfileEditor(
                        profile: profile,
                        allPanels: registry.definitions,
                        isActive: registry.activeProfile.id == profile.id,
                        isBuiltIn: PanelProfile.defaultProfiles.contains(where: { $0.id == profile.id }),
                        onSave: { updated in
                            editingProfile = updated
                            try? registry.saveProfile(updated)
                        },
                        onActivate: { registry.activateProfile(profile) },
                        onReset: {
                            try? registry.resetProfileToDefault(id: profile.id)
                            // Reflect the reset code-default back into the editor.
                            editingProfile = registry.profiles.first(where: { $0.id == profile.id })
                        },
                        onDelete: {
                            try? registry.deleteProfile(id: profile.id)
                            selectedProfileID = nil
                            editingProfile = nil
                        }
                    )
                    .id(profile.id)
                } else {
                    Text("Select a profile")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showingTemplatePicker) {
            templatePickerSheet
        }
    }

    private func profileRow(_ profile: PanelProfile) -> some View {
        Button(action: {
            selectedProfileID = profile.id
            editingProfile = profile
        }) {
            HStack {
                Text(profile.name).font(.system(size: 12))
                Spacer()
                if registry.activeProfile.id == profile.id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10))
                        .foregroundColor(themeSettings.accent)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(selectedProfileID == profile.id ? themeSettings.accent.opacity(0.25) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func addProfile() {
        showingTemplatePicker = true
    }

    @ViewBuilder
    private var templatePickerSheet: some View {
        ProfileTemplatePickerView(allPanels: registry.definitions) { panelIDs, name in
            let left = panelIDs.filter { id in
                registry.definitions.first(where: { $0.id == id })?.defaultSide == .left
            }
            let right = panelIDs.filter { id in
                registry.definitions.first(where: { $0.id == id })?.defaultSide == .right
            }
            var p = PanelProfile(name: name, leftPanelIDs: left, rightPanelIDs: right)
            p.id = UUID()
            try? registry.saveProfile(p)
            selectedProfileID = p.id
            editingProfile = p
            showingTemplatePicker = false
        } onCancel: {
            showingTemplatePicker = false
        }
    }
}

struct ProfileEditor: View {
    @State var profile: PanelProfile
    let allPanels: [PanelDefinition]
    let isActive: Bool
    let isBuiltIn: Bool
    let onSave: (PanelProfile) -> Void
    let onActivate: () -> Void
    let onReset: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                fieldGroup("Name") {
                    TextField("Profile name", text: $profile.name)
                        .onChange(of: profile.name) { _ in onSave(profile) }
                }

                fieldGroup("Left bar panels") {
                    panelIDList(ids: $profile.leftPanelIDs, otherIDs: profile.rightPanelIDs)
                }

                fieldGroup("Right bar panels") {
                    panelIDList(ids: $profile.rightPanelIDs, otherIDs: profile.leftPanelIDs)
                }

                fieldGroup("Default open: left") {
                    Picker("", selection: $profile.leftActivePanelID) {
                        Text("None").tag(Optional<String>.none)
                        ForEach(profile.leftPanelIDs, id: \.self) { id in
                            Text(panelName(id)).tag(Optional(id))
                        }
                    }
                    .labelsHidden()
                    .onChange(of: profile.leftActivePanelID) { _ in onSave(profile) }
                }

                fieldGroup("Default open: right") {
                    Picker("", selection: $profile.rightActivePanelID) {
                        Text("None").tag(Optional<String>.none)
                        ForEach(profile.rightPanelIDs, id: \.self) { id in
                            Text(panelName(id)).tag(Optional(id))
                        }
                    }
                    .labelsHidden()
                    .onChange(of: profile.rightActivePanelID) { _ in onSave(profile) }
                }

                HStack(spacing: 8) {
                    Button(isActive ? "Active" : "Set as Active") { onActivate() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isActive)
                    if isBuiltIn {
                        // Built-ins are non-deletable; offer a reset to the pristine code default instead.
                        Button("Reset to Default") {
                            onReset()
                            // Re-seed the local @State editor copy from the restored default.
                            profile = PanelProfile.defaultProfiles.first(where: { $0.id == profile.id }) ?? profile
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button("Delete") { onDelete() }
                            .foregroundColor(.red)
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
    }

    private func panelIDList(ids: Binding<[String]>, otherIDs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(ids.wrappedValue, id: \.self) { id in
                HStack {
                    Image(systemName: panelIcon(id)).font(.system(size: 11)).frame(width: 16)
                    Text(panelName(id)).font(.system(size: 11))
                    Spacer()
                    Button(action: {
                        ids.wrappedValue.removeAll { $0 == id }
                        onSave(profile)
                    }) {
                        Image(systemName: "minus.circle")
                            .foregroundColor(.red)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
                .padding(6)
                .background(DT.surface)
                .cornerRadius(4)
            }
            let unassigned = allPanels.filter { p in
                !ids.wrappedValue.contains(p.id) && !otherIDs.contains(p.id)
            }
            if !unassigned.isEmpty {
                Menu("Add panel…") {
                    ForEach(unassigned, id: \.id) { p in
                        Button(p.name) {
                            ids.wrappedValue.append(p.id)
                            onSave(profile)
                        }
                    }
                }
                .font(.system(size: 11))
            }
        }
    }

    private func fieldGroup<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
            content()
        }
    }

    private func panelName(_ id: String) -> String {
        allPanels.first(where: { $0.id == id })?.name ?? id
    }

    private func panelIcon(_ id: String) -> String {
        allPanels.first(where: { $0.id == id })?.icon ?? "square"
    }
}

struct ProfileTemplatePickerView: View {
    let allPanels: [PanelDefinition]
    let onCreate: ([String], String) -> Void
    let onCancel: () -> Void

    /// Template choices are driven by the real code defaults plus a "Blank" option — nil means Blank.
    @State private var selectedTemplateID: UUID?
    @State private var profileName = "New Profile"
    /// User-tunable checklist of which registered panels to include (seeded from the chosen template).
    @State private var includedPanelIDs: Set<String> = []

    /// Panel ids that the selected template starts with (empty for Blank).
    private func templatePanelIDs(for id: UUID?) -> [String] {
        guard let id, let profile = PanelProfile.defaultProfiles.first(where: { $0.id == id }) else {
            return []
        }
        return profile.leftPanelIDs + profile.rightPanelIDs
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("New Profile")
                .font(.headline)
                .padding()
            Divider()
            Form {
                TextField("Name", text: $profileName)
                Picker("Start from", selection: $selectedTemplateID) {
                    Text("Blank").tag(Optional<UUID>.none)
                    ForEach(PanelProfile.defaultProfiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: selectedTemplateID) { newValue in
                    includedPanelIDs = Set(templatePanelIDs(for: newValue))
                }
                // Registry-driven checklist: any registered panel can be included at creation time.
                Section("Included panels") {
                    ForEach(allPanels, id: \.id) { panel in
                        Toggle(
                            isOn: Binding(
                                get: { includedPanelIDs.contains(panel.id) },
                                set: { on in
                                    if on {
                                        includedPanelIDs.insert(panel.id)
                                    } else {
                                        includedPanelIDs.remove(panel.id)
                                    }
                                })
                        ) {
                            Label(panel.name, systemImage: panel.icon)
                                .font(.caption)
                        }
                    }
                }
            }
            .padding()
            Divider()
            HStack {
                Button("Cancel") { onCancel() }
                Spacer()
                Button("Create") {
                    // Preserve the template's panel order, then append any extra checked panels.
                    let ordered = templatePanelIDs(for: selectedTemplateID).filter { includedPanelIDs.contains($0) }
                    let extras = allPanels.map(\.id).filter {
                        includedPanelIDs.contains($0) && !ordered.contains($0)
                    }
                    onCreate(ordered + extras, profileName)
                }
                .buttonStyle(.borderedProminent)
                .disabled(profileName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 360, height: 460)
    }
}
