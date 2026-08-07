import SimpletonCore
// Sources/Simpleton/Views/PluginsPreferencesTab.swift
import SwiftUI

struct PluginsPreferencesTab: View {
    let pluginManager: PluginManager
    @State private var scripts: [ScriptPlugin] = []

    var body: some View {
        Form {
            Section {
                if scripts.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "puzzlepiece.extension")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                        Text("No plugins installed")
                            .foregroundColor(.secondary)
                        Text("Drop script folders in the scripts folder to add plugins.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }

                ForEach(scripts, id: \.name) { plugin in
                    HStack {
                        Image(systemName: "terminal")
                            .foregroundColor(.green)
                            .frame(width: 20)
                        VStack(alignment: .leading) {
                            Text(plugin.name)
                                .font(.system(size: 13))
                            HStack(spacing: 4) {
                                Text("v\(plugin.version)")
                                if let desc = plugin.manifest.description {
                                    Text("—")
                                    Text(desc)
                                }
                            }
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("Script")
                            .font(.system(size: 9))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .cornerRadius(4)
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { plugin.isEnabled },
                                set: { pluginManager.setEnabled($0, for: plugin) }
                            )
                        )
                        .labelsHidden()
                    }
                }
            } header: {
                Text("INSTALLED PLUGINS")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(.secondary)
            }

            Section {
                HStack {
                    Button("Open Scripts Folder") {
                        NSWorkspace.shared.open(AppPaths.appSupport.appendingPathComponent("scripts"))
                    }
                    Spacer()
                    Button("Reload Plugins") {
                        pluginManager.reloadScripts()
                        refresh()
                    }
                }
            }
        }
        .themedGroupedForm()
        .onAppear { refresh() }
    }

    private func refresh() {
        scripts = pluginManager.scriptPlugins
    }
}
