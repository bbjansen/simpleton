// Sources/Simpleton/Panels/ActivityBarView.swift
import SwiftUI
import UniformTypeIdentifiers

struct ActivityBarView: View {
    let side: PanelSide
    @ObservedObject var registry: PanelRegistry
    // Observe the theme so the rail's `.themedGlass` wash re-evaluates on a live theme switch —
    // otherwise the vibrancy background keeps the previous theme's color/gradient while the buttons
    // (which observe ThemeSettings themselves) flip, leaving the rail stranded on the old hue.
    @ObservedObject private var themeSettings = ThemeSettings.shared
    var onOpenSettings: (() -> Void)?

    private var panelIDs: [String] {
        side == .left
            ? registry.activeProfile.leftPanelIDs
            : registry.activeProfile.rightPanelIDs
    }

    private var activePanelID: String? {
        side == .left
            ? registry.activeProfile.leftActivePanelID
            : registry.activeProfile.rightActivePanelID
    }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(panelIDs, id: \.self) { panelID in
                if let def = registry.definitions.first(where: { $0.id == panelID }) {
                    ActivityBarButton(
                        icon: def.icon,
                        label: def.name,
                        isActive: activePanelID == panelID
                    ) {
                        togglePanel(id: panelID)
                    }
                    .onDrag { NSItemProvider(object: panelID as NSString) }
                }
            }
            Spacer()
            if let onOpenSettings = onOpenSettings {
                ActivityBarButton(icon: "gearshape", label: "Settings", isActive: false, action: onOpenSettings)
            }
        }
        .padding(.vertical, 8)
        .frame(width: 40)
        .themedGlass(DT.surface)  // theme-colored vibrancy chrome (matches the sidebar)
        .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: NSString.self) { item, _ in
                    guard let panelID = item as? String else { return }
                    DispatchQueue.main.async { movePanelToSide(panelID: panelID) }
                }
            }
            return true
        }
    }

    // MARK: - Actions

    private func togglePanel(id: String) {
        var profile = registry.activeProfile
        profile.togglePanel(id: id, on: side)
        registry.activeProfile = profile
    }

    private func movePanelToSide(panelID: String) {
        var profile = registry.activeProfile
        profile.movePanel(id: panelID, to: side)
        registry.activeProfile = profile
    }
}

struct ActivityBarButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    @ObservedObject private var themeSettings = ThemeSettings.shared

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.bounce, value: isActive)
                .foregroundColor(isActive ? themeSettings.accent : DT.textSecondary.opacity(0.7))
                .frame(width: 32, height: 32)
                .background(
                    isActive ? themeSettings.accent.opacity(0.15) : Color.clear,
                    in: .rect(cornerRadius: 6, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .help(label)
    }
}
