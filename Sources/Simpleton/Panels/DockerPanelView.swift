// Sources/Simpleton/Panels/DockerPanelView.swift
import SwiftUI
import AppKit

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
                    .foregroundStyle(.secondary)
                Spacer()
                Button { Task { await refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            Divider()
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
        .onAppear {
            Task { await refresh() }
            timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                Task { @MainActor in await self.refresh() }
            }
        }
        .onDisappear { timer?.invalidate(); timer = nil }
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
                            .fill(container.isRunning ? Color.green : Color.secondary)
                            .frame(width: 8, height: 8)
                        Text(container.name)
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.semibold)
                        Spacer()
                        containerActions(container)
                    }
                    Text(container.image)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if !container.ports.isEmpty {
                        Text(container.ports)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func containerActions(_ container: DockerContainer) -> some View {
        HStack(spacing: 8) {
            Button {
                Task { await toggleContainer(container) }
            } label: {
                Image(systemName: container.isRunning ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(container.isRunning ? Color.red : Color.green)
            Button {
                Task { await showLogs(for: container) }
            } label: {
                Image(systemName: "text.alignleft")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.secondary)
        }
    }

    @MainActor
    private func refresh() async {
        state = await loadContainers()
    }

    @MainActor
    private func toggleContainer(_ container: DockerContainer) async {
        guard let dockerPath = findDocker() else { return }
        let action = container.isRunning ? "stop" : "start"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: dockerPath)
        process.arguments = [action, container.id]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        await refresh()
    }

    @MainActor
    private func showLogs(for container: DockerContainer) async {
        guard let dockerPath = findDocker() else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: dockerPath)
        process.arguments = ["logs", "--tail", "100", container.id]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        logLines = (String(data: data, encoding: .utf8) ?? "").components(separatedBy: "\n")
        logSheetContainer = container
    }

    private func loadContainers() async -> DockerPanelState {
        guard let dockerPath = findDocker() else { return .notInstalled }
        let pingResult = await runDockerCommand(dockerPath, args: ["info", "--format", "{{.ServerVersion}}"])
        guard pingResult.exitCode == 0 else { return .notRunning }
        let runningResult = await runDockerCommand(dockerPath, args: [
            "ps", "--format", "{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}|{{.Ports}}"
        ])
        let allResult = await runDockerCommand(dockerPath, args: [
            "ps", "-a", "--format", "{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}|{{.Ports}}"
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch { return ("", 1) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "", process.terminationStatus)
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
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding()
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(logLines.indices, id: \.self) { i in
                        Text(logLines[i])
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 1)
                    }
                }
            }
        }
    }
}
