import AppKit
// Sources/Simpleton/Panels/DockerPanelView.swift
import SwiftUI

struct DockerContainer: Identifiable {
    let id: String
    let name: String
    let image: String
    let status: String
    let ports: String
    var isRunning: Bool
}

enum DockerPanelState {
    case loading
    case notInstalled
    case notRunning
    case loaded([DockerContainer])
}

struct DockerPanelView: View {
    @ObservedObject private var themeSettings = ThemeSettings.shared
    @State private var state: DockerPanelState = .loading
    @State private var logSheetContainer: DockerContainer? = nil
    @State private var logLines: [String] = []
    @State private var timer: Timer? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("DOCKER")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(DT.textPrimary)
                Spacer()
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(DT.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            ThemedDivider()
            switch state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notInstalled:
                PanelEmptyStateView(
                    icon: "shippingbox",
                    title: "Docker not installed",
                    message: "Install Docker Desktop to use this panel.",
                    actionLabel: "Get Docker",
                    action: { NSWorkspace.shared.open(URL(string: "https://www.docker.com/products/docker-desktop/")!) }
                )
            case .notRunning:
                PanelEmptyStateView(
                    icon: "shippingbox",
                    title: "Docker not running",
                    message: "Start Docker Desktop to see your containers.",
                    actionLabel: "Open Docker Desktop",
                    action: { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Docker.app")) }
                )
            case .loaded(let containers):
                dockerList(containers)
            }
        }
        .sheet(item: $logSheetContainer) { container in
            DockerLogSheet(container: container, logLines: logLines)
                .frame(width: 600, height: 400)
        }
        .themedGlass(DT.surface)
        .onAppear {
            Task { await refresh() }
            timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                Task { @MainActor in await self.refresh() }
            }
        }
        .onDisappear {
            timer?.invalidate(); timer = nil
        }
    }

    @ViewBuilder
    private func dockerList(_ containers: [DockerContainer]) -> some View {
        if containers.isEmpty {
            PanelEmptyStateView(
                icon: "shippingbox",
                title: "No containers",
                message: "No containers found. Run `docker run` to start one."
            )
        } else {
            List(containers) { container in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle()
                            .fill(container.isRunning ? DT.accentGreen : DT.textFaint)
                            .frame(width: 8, height: 8)
                        Text(container.name)
                            .font(DT.monoFont(size: 11))
                            .fontWeight(.semibold)
                            .foregroundColor(DT.textPrimary)
                        Spacer()
                        containerActions(container)
                    }
                    Text(container.image)
                        .font(.caption2)
                        .foregroundColor(DT.textTertiary)
                    if !container.ports.isEmpty {
                        Text(container.ports)
                            .font(DT.monoFont(size: 10))
                            .foregroundColor(DT.textTertiary)
                    }
                }
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func containerActions(_ container: DockerContainer) -> some View {
        HStack(spacing: 8) {
            Button {
                Task { await toggleContainer(container) }
            } label: {
                Image(systemName: container.isRunning ? "stop.fill" : "play.fill")
                    .foregroundColor(container.isRunning ? DT.accentRed : DT.accentGreen)
            }
            .buttonStyle(.plain)
            Button {
                Task { await showLogs(for: container) }
            } label: {
                Image(systemName: "text.alignleft")
                    .foregroundColor(DT.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    @MainActor
    private func refresh() async {
        state = await loadContainers()
    }

    private func toggleContainer(_ container: DockerContainer) async {
        guard let dockerPath = findDocker() else { return }
        let action = container.isRunning ? "stop" : "start"
        // Run the (potentially slow) docker command + waitUntilExit off the main
        // actor so the UI doesn't freeze during a slow stop/start.
        _ = await runDockerCommand(dockerPath, args: [action, container.id])
        await refresh()
    }

    private func showLogs(for container: DockerContainer) async {
        guard let dockerPath = findDocker() else { return }
        let result = await runDockerCommand(dockerPath, args: ["logs", "--tail", "100", container.id])
        await MainActor.run {
            logLines = result.output.components(separatedBy: "\n")
            logSheetContainer = container
        }
    }

    private func loadContainers() async -> DockerPanelState {
        guard let dockerPath = findDocker() else { return .notInstalled }
        let pingResult = await runDockerCommand(dockerPath, args: ["info", "--format", "{{.ServerVersion}}"])
        guard pingResult.exitCode == 0 else { return .notRunning }
        let runningResult = await runDockerCommand(
            dockerPath,
            args: [
                "ps", "--format", "{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}|{{.Ports}}",
            ])
        let allResult = await runDockerCommand(
            dockerPath,
            args: [
                "ps", "-a", "--format", "{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}|{{.Ports}}",
            ])
        let runningIDs = Set(
            runningResult.output.components(separatedBy: "\n")
                .filter { !$0.isEmpty }
                .compactMap { $0.components(separatedBy: "|").first }
        )
        let containers = allResult.output
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line -> DockerContainer? in
                let parts = line.components(separatedBy: "|")
                guard parts.count >= 5 else { return nil }
                return DockerContainer(
                    id: parts[0],
                    name: parts[1],
                    image: parts[2],
                    status: parts[3],
                    ports: parts[4],
                    isRunning: runningIDs.contains(parts[0])
                )
            }
        return .loaded(containers)
    }

    private func findDocker() -> String? {
        for path in ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "/usr/bin/docker"] {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    private func runDockerCommand(_ executable: String, args: [String]) async -> (output: String, exitCode: Int32) {
        // Detached so the blocking run()/waitUntilExit() never executes on the
        // MainActor and can't freeze the UI.
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
            } catch { return ("", 1) }
            // Read output before waitUntilExit to avoid a pipe-buffer deadlock.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (String(data: data, encoding: .utf8) ?? "", process.terminationStatus)
        }.value
    }
}

struct DockerLogSheet: View {
    let container: DockerContainer
    let logLines: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Logs — \(container.name)")
                    .font(.headline)
                    .foregroundColor(DT.textPrimary)
                Spacer()
                Button("Close") { dismiss() }
                    .tint(DT.accent)
            }
            .padding()
            ThemedDivider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(logLines.indices, id: \.self) { i in
                        Text(logLines[i])
                            .font(DT.monoFont(size: 10))
                            .foregroundColor(DT.textSecondary)
                            .textSelection(.enabled)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 1)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(DT.surface)
    }
}
