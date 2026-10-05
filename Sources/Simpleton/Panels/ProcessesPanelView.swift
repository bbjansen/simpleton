import AppKit
// Sources/Simpleton/Panels/ProcessesPanelView.swift
import SwiftUI

struct ProcessEntry: Identifiable {
    let id: Int32
    let pid: Int32
    let cpu: Double
    let mem: Double
    let command: String
}

struct ProcessesPanelView: View {
    @ObservedObject private var themeSettings = ThemeSettings.shared

    @State private var processes: [ProcessEntry] = []

    var body: some View {
        ClientPanelScaffold(
            title: "PROCESSES",
            availability: .ready,
            autoRefresh: 3,
            onRefresh: { await load() }
        ) {
            if processes.isEmpty {
                PanelEmptyStateView(
                    icon: "cpu",
                    title: "No processes",
                    message: "Running processes will appear here."
                )
            } else {
                List(processes) { proc in
                    processRow(proc)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .themedGlass(DT.surface)
    }

    @ViewBuilder
    private func processRow(_ proc: ProcessEntry) -> some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 1) {
                Text(proc.command)
                    .font(DT.monoFont(size: 11))
                    .foregroundColor(DT.textPrimary)
                    .lineLimit(1)
                Text(
                    "PID \(proc.pid)  CPU \(String(format: "%.1f", proc.cpu))%  MEM \(String(format: "%.1f", proc.mem))%"
                )
                .font(DT.monoFont(size: 10))
                .foregroundColor(DT.textTertiary)
            }
            Spacer()
            Button {
                kill(proc.pid, SIGTERM)
                let pid = proc.pid
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    kill(pid, SIGKILL)
                }
                Task { await load() }
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundColor(DT.accentRed)
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(Color.clear)
    }

    @MainActor
    private func load() async {
        processes = await fetchProcesses()
    }

    private func fetchProcesses() async -> [ProcessEntry] {
        // Screenshot demo mode: a fixed, fake process list instead of the machine's real processes
        // (which would leak what apps the user runs). Gated by env; off in normal use.
        if ProcessInfo.processInfo.environment["SIMPLETON_SHOT_DEMO"] != nil {
            return [
                ProcessEntry(id: 412, pid: 412, cpu: 2.4, mem: 1.1, command: "zsh"),
                ProcessEntry(id: 588, pid: 588, cpu: 8.1, mem: 3.4, command: "node"),
                ProcessEntry(id: 731, pid: 731, cpu: 0.6, mem: 2.2, command: "docker"),
                ProcessEntry(id: 902, pid: 902, cpu: 1.3, mem: 0.9, command: "postgres"),
                ProcessEntry(id: 1044, pid: 1044, cpu: 0.2, mem: 0.5, command: "ssh"),
                ProcessEntry(id: 1210, pid: 1210, cpu: 12.5, mem: 6.7, command: "Simpleton"),
                ProcessEntry(id: 1355, pid: 1355, cpu: 0.1, mem: 0.3, command: "git"),
                ProcessEntry(id: 1489, pid: 1489, cpu: 3.0, mem: 1.8, command: "nvim"),
            ]
        }
        // Use -U to filter to current user directly, avoiding per-process sysctl calls
        let currentUser = NSUserName()
        // Run the process + waitUntilExit off the MainActor so a slow `ps` can't
        // freeze the UI.
        let output: String? = await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["-U", currentUser, "-o", "pid,pcpu,pmem,comm"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
            } catch {
                return nil
            }
            // Read output BEFORE waitUntilExit to avoid pipe buffer deadlock
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8)
        }.value
        guard let output else { return [] }
        return output.components(separatedBy: "\n")
            .dropFirst()  // header
            .compactMap { line -> ProcessEntry? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                guard parts.count >= 4,
                    let pid = Int32(parts[0]),
                    let cpu = Double(parts[1]),
                    let mem = Double(parts[2])
                else { return nil }
                // comm may contain spaces — rejoin everything from index 3 onward
                let fullPath = parts[3...].joined(separator: " ")
                let command = URL(fileURLWithPath: fullPath).lastPathComponent
                return ProcessEntry(id: pid, pid: pid, cpu: cpu, mem: mem, command: command)
            }
            .sorted { $0.cpu > $1.cpu }
            .prefix(50)
            .map { $0 }
    }
}
