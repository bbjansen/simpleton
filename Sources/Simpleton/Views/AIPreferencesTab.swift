import AppKit
// Sources/Simpleton/Views/AIPreferencesTab.swift
import SwiftUI

struct AIPreferencesTab: View {
    @State var config: AIConfig
    let onChanged: (AIConfig) -> Void

    @State private var apiKeyText = ""
    @State private var hasKey = false
    @State private var keyStatus: KeyStatus = .unknown
    @State private var isTesting = false

    // Model dropdown state
    @State private var models: [String] = []
    @State private var loadingModels = false
    @State private var modelError: String?

    enum KeyStatus {
        case unknown, valid, invalid(String), testing
    }

    private var preset: ProviderPreset { config.provider.preset }

    var body: some View {
        Form {
            Section {
                Toggle("Enable AI features", isOn: $config.enabled)
                    .onChange(of: config.enabled) { onChanged(config) }
            } header: {
                HStack {
                    sectionLabel("AI FEATURES")
                    Spacer()
                    Image(systemName: "sparkles").font(.system(size: 11)).foregroundColor(.purple)
                }
            }

            if config.enabled {
                providerSection
                if config.provider != .ollama { apiKeySection }
                modelSection
                privacySection
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshKeyStatus()
            autoLoadModels()
        }
    }

    // MARK: - Provider

    private var providerSection: some View {
        Section {
            Picker("Provider", selection: $config.provider) {
                ForEach(AIProvider.allCases, id: \.self) { provider in
                    Text(provider.preset.displayName).tag(provider)
                }
            }
            .onChange(of: config.provider) {
                apiKeyText = ""
                refreshKeyStatus()
                config.model = preset.defaultModel
                onChanged(config)
                models = []
                modelError = nil
                autoLoadModels()
            }
            if preset.transport == .openAICompatible && config.provider != .ollama && config.provider != .custom {
                Text("Endpoint: \(preset.fixedBaseURL ?? "")")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            if !preset.supportsTools {
                Label(
                    "Tool use runs via fenced command blocks for this provider.", systemImage: "wrench.and.screwdriver"
                )
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
        } header: {
            sectionLabel("PROVIDER")
        }
    }

    // MARK: - API key

    private var apiKeySection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "1.circle.fill").foregroundColor(.purple).font(.system(size: 16))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Get your API key").font(.system(size: 13, weight: .medium))
                    Text(preset.keyDescription).font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
                if preset.keyPageURL != nil {
                    Button(action: openProviderKeyPage) {
                        HStack(spacing: 4) {
                            Text("Open \(preset.displayName)")
                            Image(systemName: "arrow.up.right.square")
                        }
                        .font(.system(size: 12))
                    }
                }
            }
            .padding(.vertical, 4)

            HStack(spacing: 12) {
                Image(systemName: "2.circle.fill").foregroundColor(.purple).font(.system(size: 16))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Paste it here (stored in macOS Keychain)").font(.system(size: 13, weight: .medium))
                    HStack {
                        SecureField(
                            preset.apiKeyPlaceholder.isEmpty ? "API key" : preset.apiKeyPlaceholder, text: $apiKeyText
                        )
                        .textFieldStyle(.roundedBorder)
                        Button(action: saveAndTestKey) {
                            if isTesting {
                                ProgressView().scaleEffect(0.6).frame(width: 50)
                            } else {
                                Text(hasKey ? "Update" : "Save").frame(width: 50)
                            }
                        }
                        .disabled(apiKeyText.isEmpty || isTesting)
                    }
                }
            }
            .padding(.vertical, 4)

            keyStatusView
        } header: {
            sectionLabel("API KEY")
        }
    }

    @ViewBuilder
    private var keyStatusView: some View {
        switch keyStatus {
        case .valid:
            statusRow("checkmark.circle.fill", .green, "API key verified and stored in Keychain")
        case .invalid(let error):
            statusRow("xmark.circle.fill", .red, error)
        case .testing:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.6)
                Text("Testing API key…").foregroundColor(.secondary)
            }
            .font(.system(size: 12)).padding(.vertical, 2)
        case .unknown where hasKey:
            HStack(spacing: 6) {
                Image(systemName: "key.fill").foregroundColor(.secondary)
                Text("API key stored in Keychain").foregroundColor(.secondary)
                Spacer()
                Button("Test") { testExistingKey() }.font(.system(size: 11))
                Button("Remove") { removeKey() }.font(.system(size: 11)).foregroundColor(.red)
            }
            .font(.system(size: 12)).padding(.vertical, 2)
        default:
            EmptyView()
        }
    }

    // MARK: - Model

    private var modelSection: some View {
        Section {
            HStack {
                if loadingModels {
                    ProgressView().scaleEffect(0.6).frame(width: 18)
                    Text("Loading models…").font(.system(size: 12)).foregroundColor(.secondary)
                    Spacer()
                } else if !models.isEmpty {
                    Picker("Model", selection: $config.model) {
                        ForEach(modelOptions, id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: config.model) { onChanged(config) }
                } else {
                    Text("Model").foregroundColor(.primary)
                    Spacer()
                    Text("Load the list →").font(.system(size: 11)).foregroundColor(.secondary)
                }
                Button(action: loadModels) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Fetch available models from \(preset.displayName)")
                .disabled(loadingModels)
            }

            TextField("Model name", text: $config.model)
                .onChange(of: config.model) { onChanged(config) }
            Text(preset.modelHint).font(.system(size: 11)).foregroundColor(.secondary)
            if let modelError {
                Text(modelError).font(.system(size: 11)).foregroundColor(.orange)
            }

            if config.provider == .ollama {
                TextField("Ollama URL", text: $config.localOllamaURL)
                    .onChange(of: config.localOllamaURL) { onChanged(config) }
                Text("Default: http://localhost:11434").font(.system(size: 11)).foregroundColor(.secondary)
            }
            if config.provider == .custom {
                TextField(
                    "Base URL",
                    text: Binding(
                        get: { config.baseURL ?? "" },
                        set: { config.baseURL = $0.isEmpty ? nil : $0 }
                    )
                )
                .onChange(of: config.baseURL) { onChanged(config) }
                Text("OpenAI-compatible endpoint, e.g. https://api.example.com/v1").font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        } header: {
            sectionLabel("MODEL")
        }
    }

    /// The picker options — fetched models plus the current model if it isn't in the list,
    /// so the selection always has a matching tag.
    private var modelOptions: [String] {
        models.contains(config.model) || config.model.isEmpty ? models : [config.model] + models
    }

    // MARK: - Privacy

    private var privacySection: some View {
        Section {
            if config.provider == .ollama {
                Label("All data stays on your machine", systemImage: "lock.shield.fill")
                    .font(.system(size: 12, weight: .medium)).foregroundColor(.green)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What is sent to \(preset.displayName):").font(.system(size: 12, weight: .medium))
                    VStack(alignment: .leading, spacing: 4) {
                        privacyRow("Working directory path", icon: "folder", sent: true)
                        privacyRow("Shell type & OS version", icon: "terminal", sent: true)
                        privacyRow("Last 5 commands", icon: "clock", sent: true)
                        privacyRow("Selected text (Explain only)", icon: "text.cursor", sent: true)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        privacyRow("Environment variables", icon: "key", sent: false)
                        privacyRow("SSH keys & passwords", icon: "lock.shield", sent: false)
                        privacyRow("Full scrollback buffer", icon: "doc.text", sent: false)
                    }
                }
            }
        } header: {
            sectionLabel("PRIVACY")
        }
    }

    // MARK: - Small views

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundColor(.secondary)
    }

    private func statusRow(_ icon: String, _ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundColor(color)
            Text(text).foregroundColor(color)
        }
        .font(.system(size: 12)).padding(.vertical, 2)
    }

    private func privacyRow(_ text: String, icon: String, sent: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: sent ? "checkmark.circle" : "xmark.circle")
                .foregroundColor(sent ? .secondary : .green).font(.system(size: 10))
            Image(systemName: icon).foregroundColor(.secondary).font(.system(size: 10)).frame(width: 14)
            Text(text).font(.system(size: 11)).foregroundColor(sent ? .secondary : .green)
        }
    }

    // MARK: - Models

    private func autoLoadModels() {
        guard config.enabled else { return }
        if config.provider == .ollama || AIKeychain.hasAPIKey(for: config.provider) {
            loadModels()
        }
    }

    private func loadModels() {
        loadingModels = true
        modelError = nil
        let key = AIKeychain.retrieveAPIKey(for: config.provider)
        let cfg = config
        Task {
            let result = await ModelFetcher.fetch(config: cfg, apiKey: key)
            await MainActor.run {
                loadingModels = false
                models = result.models
                modelError = result.error
            }
        }
    }

    // MARK: - Key actions

    private func openProviderKeyPage() {
        guard let page = preset.keyPageURL, let url = URL(string: page) else { return }
        NSWorkspace.shared.open(url)
    }

    private func saveAndTestKey() {
        let key = apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        _ = AIKeychain.storeAPIKey(key, for: config.provider)
        hasKey = true
        apiKeyText = ""
        validate(using: key)
    }

    private func testExistingKey() {
        guard let key = AIKeychain.retrieveAPIKey(for: config.provider) else { return }
        validate(using: key)
    }

    /// Validate a key by listing the provider's models — a pure auth check that (unlike a chat
    /// completion) does not depend on the project having access to a specific model. Populates the
    /// model dropdown on success.
    private func validate(using key: String) {
        keyStatus = .testing
        isTesting = true
        let cfg = config
        Task {
            let result = await ModelFetcher.fetch(config: cfg, apiKey: key)
            await MainActor.run {
                isTesting = false
                if !result.models.isEmpty {
                    models = result.models
                    modelError = nil
                    keyStatus = .valid
                } else if let error = result.error {
                    keyStatus =
                        error.localizedCaseInsensitiveContains("unauthorized")
                        ? .invalid("Invalid API key — check and try again")
                        : .invalid(error)
                } else {
                    keyStatus = .valid
                }
            }
        }
    }

    private func removeKey() {
        AIKeychain.deleteAPIKey(for: config.provider)
        hasKey = false
        keyStatus = .unknown
        models = []
    }

    private func refreshKeyStatus() {
        hasKey = AIKeychain.hasAPIKey(for: config.provider)
        keyStatus = .unknown
    }
}
