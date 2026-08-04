// Sources/Simpleton/Panels/ActivityBarView.swift
import SwiftUI
import UniformTypeIdentifiers

struct ActivityBarView: View {
    let side: PanelSide
    @ObservedObject var registry: PanelRegistry
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
        .background(Color(nsColor: NSColor(white: 0.08, alpha: 1)))
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

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(isActive ? .accentColor : .secondary)
                .frame(width: 32, height: 32)
                .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help(label)
    }
}
