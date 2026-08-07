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
    @State private var timer: Timer? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PROCESSES")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(DT.textPrimary)
                Spacer()
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(DT.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            ThemedDivider()
            if processes.isEmpty {
                PanelEmptyStateView(
                    icon: "cpu",
                    title: "No processes",
                    message: "Running processes will appear here."
                )
            } else {
                List(processes) { proc in
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
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .themedGlass(DT.surface)
        .onAppear {
            Task { await load() }
            timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                Task { @MainActor in await self.load() }
            }
        }
        .onDisappear {
            timer?.invalidate(); timer = nil
        }
    }

    @MainActor
    private func load() async {
        processes = await fetchProcesses()
    }

    private func fetchProcesses() async -> [ProcessEntry] {
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
