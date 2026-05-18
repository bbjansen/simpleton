// Sources/Simpleton/Views/ProfilesPreferencesTab.swift
import SwiftUI
import SimpletonCore

struct ProfilesPreferencesTab: View {
    @ObservedObject var registry: PanelRegistry
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
                        isDefault: PanelProfile.defaultProfiles.contains(where: { $0.id == profile.id }),
                        onSave: { updated in
                            editingProfile = updated
                            try? registry.saveProfile(updated)
                        },
                        onActivate: { registry.activateProfile(profile) },
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
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(selectedProfileID == profile.id ? Color.accentColor.opacity(0.3) : Color.clear)
            .cornerRadius(6)
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
    let isDefault: Bool
    let onSave: (PanelProfile) -> Void
    let onActivate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isDefault {
                    Text("Built-in profile — read only")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                        .padding(8)
                        .background(Color(nsColor: NSColor(white: 0.1, alpha: 1)))
                        .cornerRadius(6)
                }

                fieldGroup("Name") {
                    TextField("Profile name", text: $profile.name)
                        .disabled(isDefault)
                        .onChange(of: profile.name) { _ in if !isDefault { onSave(profile) } }
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
                    .disabled(isDefault)
                    .onChange(of: profile.leftActivePanelID) { _ in if !isDefault { onSave(profile) } }
                }

                fieldGroup("Default open: right") {
                    Picker("", selection: $profile.rightActivePanelID) {
                        Text("None").tag(Optional<String>.none)
                        ForEach(profile.rightPanelIDs, id: \.self) { id in
                            Text(panelName(id)).tag(Optional(id))
                        }
                    }
                    .labelsHidden()
                    .disabled(isDefault)
                    .onChange(of: profile.rightActivePanelID) { _ in if !isDefault { onSave(profile) } }
                }

                HStack(spacing: 8) {
                    Button(isActive ? "Active" : "Set as Active") { onActivate() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isActive)
                    if !isDefault {
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
                    if !isDefault {
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
                }
                .padding(6)
                .background(Color(nsColor: NSColor(white: 0.1, alpha: 1)))
                .cornerRadius(4)
            }
            if !isDefault {
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

    @State private var selectedTemplate: TemplateOption = .blank
    @State private var profileName = "New Profile"

    enum TemplateOption: String, CaseIterable, Identifiable {
        case blank      = "Blank"
        case general    = "General"
        case developer  = "Developer"
        case devops     = "DevOps"
        var id: String { rawValue }
    }

    private var templatePanelIDs: [String] {
        switch selectedTemplate {
        case .blank:
            return []
        case .general:
            return (PanelProfile.defaultProfiles.first(where: { $0.name == "General" })).map {
                $0.leftPanelIDs + $0.rightPanelIDs
            } ?? []
        case .developer:
            return (PanelProfile.defaultProfiles.first(where: { $0.name == "Developer" })).map {
                $0.leftPanelIDs + $0.rightPanelIDs
            } ?? []
        case .devops:
            return (PanelProfile.defaultProfiles.first(where: { $0.name == "DevOps" })).map {
                $0.leftPanelIDs + $0.rightPanelIDs
            } ?? []
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("New Profile")
                .font(.headline)
                .padding()
            Divider()
            Form {
                TextField("Name", text: $profileName)
                Picker("Start from", selection: $selectedTemplate) {
                    ForEach(TemplateOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.radioGroup)
                if selectedTemplate != .blank {
                    Section("Included panels") {
                        ForEach(templatePanelIDs, id: \.self) { id in
                            if let panel = allPanels.first(where: { $0.id == id }) {
                                Label(panel.name, systemImage: panel.icon)
                                    .font(.caption)
                            }
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
                    onCreate(templatePanelIDs, profileName)
                }
                .buttonStyle(.borderedProminent)
                .disabled(profileName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 360, height: 400)
    }
}
