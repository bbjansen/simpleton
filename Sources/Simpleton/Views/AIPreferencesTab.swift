// Sources/Simpleton/Views/AIPreferencesTab.swift
import SwiftUI
import AppKit

struct AIPreferencesTab: View {
    @State var config: AIConfig
    let onChanged: (AIConfig) -> Void

    @State private var apiKeyText = ""
    @State private var hasKey = false
    @State private var keyStatus: KeyStatus = .unknown
    @State private var isTesting = false

    enum KeyStatus {
        case unknown, valid, invalid(String), testing
    }

    var body: some View {
        Form {
            // Enable toggle
            Section {
                Toggle("Enable AI features", isOn: $config.enabled)
                    .onChange(of: config.enabled) { onChanged(config) }
            } header: {
                HStack {
                    Text("AI FEATURES")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.5)
                        .foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundColor(.purple)
                }
            }

            if config.enabled {
                // Provider picker
                Section {
                    Picker("Provider", selection: $config.provider) {
                        Text("Anthropic (Claude)").tag(AIProvider.anthropic)
                        Text("OpenAI (GPT)").tag(AIProvider.openai)
                        Text("Ollama (Local)").tag(AIProvider.ollama)
                        Text("Custom endpoint").tag(AIProvider.custom)
                    }
                    .onChange(of: config.provider) {
                        onChanged(config)
                        refreshKeyStatus()
                        apiKeyText = ""
                        // Set default model for provider
                        switch config.provider {
                        case .anthropic: config.model = "claude-sonnet-4-20250514"
                        case .openai: config.model = "gpt-4o"
                        case .ollama: config.model = "llama3"
                        case .custom: config.model = "gpt-4o"
                        }
                        onChanged(config)
                    }
                } header: {
                    Text("PROVIDER")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.5)
                        .foregroundColor(.secondary)
                }

                // API Key section (not for Ollama)
                if config.provider != .ollama {
                    Section {
                        // Step 1: Get key button
                        HStack(spacing: 12) {
                            Image(systemName: "1.circle.fill")
                                .foregroundColor(.purple)
                                .font(.system(size: 16))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Get your API key")
                                    .font(.system(size: 13, weight: .medium))
                                Text(providerKeyDescription)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(action: openProviderKeyPage) {
                                HStack(spacing: 4) {
                                    Text("Open \(providerName)")
                                    Image(systemName: "arrow.up.right.square")
                                }
                                .font(.system(size: 12))
                            }
                        }
                        .padding(.vertical, 4)

                        // Step 2: Paste key
                        HStack(spacing: 12) {
                            Image(systemName: "2.circle.fill")
                                .foregroundColor(.purple)
                                .font(.system(size: 16))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Paste it here (stored in macOS Keychain)")
                                    .font(.system(size: 13, weight: .medium))
                                HStack {
                                    SecureField(apiKeyPlaceholder, text: $apiKeyText)
                                        .textFieldStyle(.roundedBorder)
                                    Button(action: saveAndTestKey) {
                                        if isTesting {
                                            ProgressView()
                                                .scaleEffect(0.6)
                                                .frame(width: 50)
                                        } else {
                                            Text(hasKey ? "Update" : "Save")
                                                .frame(width: 50)
                                        }
                                    }
                                    .disabled(apiKeyText.isEmpty || isTesting)
                                }
                            }
                        }
                        .padding(.vertical, 4)

                        // Status indicator
                        switch keyStatus {
                        case .valid:
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("API key verified and stored in Keychain")
                                    .foregroundColor(.green)
                            }
                            .font(.system(size: 12))
                            .padding(.vertical, 2)
                        case .invalid(let error):
                            HStack(spacing: 6) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text(error)
                                    .foregroundColor(.red)
                            }
                            .font(.system(size: 12))
                            .padding(.vertical, 2)
                        case .unknown where hasKey:
                            HStack(spacing: 6) {
                                Image(systemName: "key.fill")
                                    .foregroundColor(.secondary)
                                Text("API key stored in Keychain")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("Test") { testExistingKey() }
                                    .font(.system(size: 11))
                                Button("Remove") { removeKey() }
                                    .font(.system(size: 11))
                                    .foregroundColor(.red)
                            }
                            .font(.system(size: 12))
                            .padding(.vertical, 2)
                        case .testing:
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("Testing API key...")
                                    .foregroundColor(.secondary)
                            }
                            .font(.system(size: 12))
                            .padding(.vertical, 2)
                        default:
                            EmptyView()
                        }
                    } header: {
                        Text("API KEY")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1.5)
                            .foregroundColor(.secondary)
                    }
                }

                // Model config
                Section {
                    TextField("Model", text: $config.model)
                        .onChange(of: config.model) { onChanged(config) }
                    Text(modelHelpText)
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
                        Text("OpenAI-compatible API endpoint (e.g. https://api.example.com/v1)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("MODEL")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.5)
                        .foregroundColor(.secondary)
                }

                // Privacy
                Section {
                    if config.provider == .ollama {
                        Label("All data stays on your machine", systemImage: "lock.shield.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.green)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What is sent to \(providerName):")
                                .font(.system(size: 12, weight: .medium))
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
                    Text("PRIVACY")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.5)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshKeyStatus() }
    }

    // MARK: - Helpers

    private var providerName: String {
        switch config.provider {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .ollama: return "Ollama"
        case .custom: return "Provider"
        }
    }

    private var providerKeyDescription: String {
        switch config.provider {
        case .anthropic: return "Create a key at console.anthropic.com — free tier available"
        case .openai: return "Create a key at platform.openai.com/api-keys"
        case .custom: return "Get an API key from your provider"
        default: return ""
        }
    }

    private var apiKeyPlaceholder: String {
        switch config.provider {
        case .anthropic: return "sk-ant-api03-..."
        case .openai: return "sk-proj-..."
        case .custom: return "API key"
        default: return "API key"
        }
    }

    private var modelHelpText: String {
        switch config.provider {
        case .anthropic: return "Recommended: claude-sonnet-4-20250514 (fast) or claude-opus-4-20250514 (powerful)"
        case .openai: return "Recommended: gpt-4o (balanced) or gpt-4o-mini (fast & cheap)"
        case .ollama: return "Run `ollama list` to see installed models. Try: llama3, codellama, mistral"
        case .custom: return "Model name as your provider expects it"
        }
    }

    private func privacyRow(_ text: String, icon: String, sent: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: sent ? "checkmark.circle" : "xmark.circle")
                .foregroundColor(sent ? .secondary : .green)
                .font(.system(size: 10))
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .font(.system(size: 10))
                .frame(width: 14)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(sent ? .secondary : .green)
        }
    }

    private func openProviderKeyPage() {
        let url: URL
        switch config.provider {
        case .anthropic:
            url = URL(string: "https://console.anthropic.com/settings/keys")!
        case .openai:
            url = URL(string: "https://platform.openai.com/api-keys")!
        case .custom:
            guard let customURL = URL(string: config.baseURL ?? "https://example.com") else { return }
            url = customURL
        default:
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func saveAndTestKey() {
        guard !apiKeyText.isEmpty else { return }
        _ = AIKeychain.storeAPIKey(apiKeyText, for: config.provider)
        hasKey = true
        keyStatus = .testing
        isTesting = true

        let keyToTest = apiKeyText
        apiKeyText = ""

        // Test the key with a minimal API call
        Task {
            let result = await testAPIKey(keyToTest)
            await MainActor.run {
                isTesting = false
                keyStatus = result
            }
        }
    }

    private func testExistingKey() {
        guard let key = AIKeychain.retrieveAPIKey(for: config.provider) else { return }
        keyStatus = .testing
        isTesting = true
        Task {
            let result = await testAPIKey(key)
            await MainActor.run {
                isTesting = false
                keyStatus = result
            }
        }
    }

    private func removeKey() {
        AIKeychain.deleteAPIKey(for: config.provider)
        hasKey = false
        keyStatus = .unknown
    }

    private func refreshKeyStatus() {
        hasKey = AIKeychain.hasAPIKey(for: config.provider)
        keyStatus = .unknown
    }

    private func testAPIKey(_ key: String) async -> KeyStatus {
        do {
            guard let (url, headers, body) = buildTestRequest(key: key) else { return .invalid("Invalid endpoint URL") }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 10
            for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
            request.httpBody = body

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .invalid("No response from server")
            }

            if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                return .valid
            } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                return .invalid("Invalid API key — check and try again")
            } else {
                let body = String(data: data, encoding: .utf8) ?? ""
                return .invalid("Error \(httpResponse.statusCode): \(body.prefix(100))")
            }
        } catch {
            return .invalid("Connection failed: \(error.localizedDescription)")
        }
    }

    private func buildTestRequest(key: String) -> (URL, [(String, String)], Data?)? {
        switch config.provider {
        case .anthropic:
            let url = URL(string: "https://api.anthropic.com/v1/messages")!
            let headers = [
                ("Content-Type", "application/json"),
                ("x-api-key", key),
                ("anthropic-version", "2023-06-01"),
            ]
            let body = try? JSONSerialization.data(withJSONObject: [
                "model": config.model,
                "max_tokens": 1,
                "messages": [["role": "user", "content": "hi"]]
            ])
            return (url, headers, body)

        case .openai, .custom:
            let baseURL = config.provider == .custom ? (config.baseURL ?? "https://api.openai.com/v1") : "https://api.openai.com/v1"
            guard let url = URL(string: "\(baseURL)/chat/completions") else { return nil }
            var headers = [("Content-Type", "application/json")]
            if !key.isEmpty { headers.append(("Authorization", "Bearer \(key)")) }
            let body = try? JSONSerialization.data(withJSONObject: [
                "model": config.model,
                "max_tokens": 1,
                "messages": [["role": "user", "content": "hi"]]
            ])
            return (url, headers, body)

        case .ollama:
            guard let url = URL(string: "\(config.localOllamaURL)/v1/chat/completions") else { return nil }
            let headers = [("Content-Type", "application/json")]
            let body = try? JSONSerialization.data(withJSONObject: [
                "model": config.model,
                "max_tokens": 1,
                "messages": [["role": "user", "content": "hi"]]
            ])
            return (url, headers, body)
        }
    }
}
