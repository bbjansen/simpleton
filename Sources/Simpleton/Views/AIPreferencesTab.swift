// Sources/Simpleton/Views/AIPreferencesTab.swift
import SwiftUI

struct AIPreferencesTab: View {
    @State var config: AIConfig
    let onChanged: (AIConfig) -> Void

    @State private var apiKeyText = ""
    @State private var hasKey = false

    var body: some View {
        Form {
            Section {
                Toggle("Enable AI features", isOn: $config.enabled)
                    .onChange(of: config.enabled) { onChanged(config) }
                Text("AI features require an API key from your chosen provider.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } header: {
                Text("AI FEATURES")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(.secondary)
            }

            if config.enabled {
                Section {
                    Picker("Provider", selection: $config.provider) {
                        Text("Anthropic (Claude)").tag(AIProvider.anthropic)
                        Text("OpenAI (GPT)").tag(AIProvider.openai)
                        Text("Ollama (Local)").tag(AIProvider.ollama)
                        Text("Custom endpoint").tag(AIProvider.custom)
                    }
                    .onChange(of: config.provider) {
                        onChanged(config)
                        hasKey = AIKeychain.hasAPIKey(for: config.provider)
                        apiKeyText = ""
                    }

                    if config.provider != .ollama {
                        HStack {
                            SecureField("API Key", text: $apiKeyText)
                            Button(hasKey ? "Update" : "Save") {
                                if !apiKeyText.isEmpty {
                                    _ = AIKeychain.storeAPIKey(apiKeyText, for: config.provider)
                                    hasKey = true
                                    apiKeyText = ""
                                }
                            }
                        }
                        if hasKey {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 11))
                                Text("API key stored in Keychain")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    TextField("Model", text: $config.model)
                        .onChange(of: config.model) { onChanged(config) }
                    Text("e.g. claude-sonnet-4-20250514, gpt-4o, llama3")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    if config.provider == .ollama {
                        TextField("Ollama URL", text: $config.localOllamaURL)
                            .onChange(of: config.localOllamaURL) { onChanged(config) }
                        Text("Default: http://localhost:11434")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    if config.provider == .custom {
                        TextField("Base URL", text: Binding(
                            get: { config.baseURL ?? "" },
                            set: { config.baseURL = $0.isEmpty ? nil : $0 }
                        ))
                        .onChange(of: config.baseURL) { onChanged(config) }
                        Text("OpenAI-compatible API endpoint")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("PROVIDER")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.5)
                        .foregroundColor(.secondary)
                }

                Section {
                    Text("AI features send limited context to your chosen provider:")
                        .font(.system(size: 11))
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Current working directory", systemImage: "folder")
                        Label("Shell type and OS version", systemImage: "terminal")
                        Label("Recent commands (last 5)", systemImage: "clock")
                        Label("Selected text (when you choose 'Explain')", systemImage: "text.cursor")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                    Text("Never sent: environment variables, SSH keys, passwords, full scrollback")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.green)

                    if config.provider == .ollama {
                        Label("Using local model — no data leaves your machine", systemImage: "lock.shield")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                    }
                } header: {
                    Text("PRIVACY")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.5)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            hasKey = AIKeychain.hasAPIKey(for: config.provider)
        }
    }
}
