// Sources/Simpleton/Panels/EnvironmentPanelView.swift
import SwiftUI
import AppKit

struct EnvironmentPanelView: View {
    let shell: String
    let currentPaneProvider: () -> PaneController?

    @State private var entries: [(key: String, value: String)] = []
    @State private var query = ""
    @State private var isLoading = false
    @State private var isSSH = false

    private var filtered: [(key: String, value: String)] {
        query.isEmpty ? entries : entries.filter {
            $0.key.localizedCaseInsensitiveContains(query) ||
            $0.value.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Filter…", text: $query)
                    .textFieldStyle(.plain)
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }
            .padding(8)
            Divider()
            if isSSH {
                PanelEmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Not available",
                    message: "Environment is not available for remote SSH connections."
                )
            } else if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                PanelEmptyStateView(
                    icon: "terminal",
                    title: "No environment",
                    message: "Tap refresh to load environment variables."
                )
            } else {
                List(filtered, id: \.key) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.key)
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.semibold)
                        Text(entry.value)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.value, forType: .string)
                    }
                }
                .listStyle(.plain)
            }
        }
        .onAppear {
            let pane = currentPaneProvider()
            if case .ssh = pane?.connectionType { isSSH = true; return }
            Task { await refresh() }
        }
    }

    @MainActor
    private func refresh() async {
        let pane = currentPaneProvider()
        if case .ssh = pane?.connectionType { isSSH = true; return }
        isSSH = false
        isLoading = true
        defer { isLoading = false }
        entries = await loadEnv(shell: shell)
    }

    private func loadEnv(shell: String) async -> [(key: String, value: String)] {
        let shellName = URL(fileURLWithPath: shell).lastPathComponent
        let resolvedShell: String
        if shellName == "$SHELL" || shellName.isEmpty {
            resolvedShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        } else {
            resolvedShell = shell
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolvedShell)
        process.arguments = ["-l", "-c", "env"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return output.components(separatedBy: "\n")
            .compactMap { line -> (key: String, value: String)? in
                guard let eq = line.firstIndex(of: "=") else { return nil }
                let key = String(line[..<eq])
                let value = String(line[line.index(after: eq)...])
                return key.isEmpty ? nil : (key: key, value: value)
            }
            .sorted { $0.key < $1.key }
    }
}
