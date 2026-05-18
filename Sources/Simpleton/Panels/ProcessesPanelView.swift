// Sources/Simpleton/Panels/ProcessesPanelView.swift
import SwiftUI
import AppKit

struct ProcessEntry: Identifiable {
    let id: Int32
    let pid: Int32
    let cpu: Double
    let mem: Double
    let command: String
}

struct ProcessesPanelView: View {
    @State private var processes: [ProcessEntry] = []
    @State private var timer: Timer? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PROCESSES")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            Divider()
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
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                            Text("PID \(proc.pid)  CPU \(String(format: "%.1f", proc.cpu))%  MEM \(String(format: "%.1f", proc.mem))%")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            kill(proc.pid, SIGTERM)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                kill(proc.pid, SIGKILL)
                            }
                            Task { await load() }
                        } label: {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
            }
        }
        .onAppear {
            Task { await load() }
            timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                Task { @MainActor in await self.load() }
            }
        }
        .onDisappear { timer?.invalidate(); timer = nil }
    }

    @MainActor
    private func load() async {
        processes = await fetchProcesses()
    }

    private func fetchProcesses() async -> [ProcessEntry] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-eo", "pid,pcpu,pmem,comm"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run(); process.waitUntilExit() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        let currentUID = getuid()
        return output.components(separatedBy: "\n")
            .dropFirst() // header
            .compactMap { line -> ProcessEntry? in
                let parts = line.trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                guard parts.count >= 4,
                      let pid = Int32(parts[0]),
                      let cpu = Double(parts[1]),
                      let mem = Double(parts[2]) else { return nil }
                let command = URL(fileURLWithPath: parts[3]).lastPathComponent
                // Filter to current user's processes
                var kinfo = kinfo_proc()
                var size = MemoryLayout<kinfo_proc>.size
                var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
                guard sysctl(&mib, 4, &kinfo, &size, nil, 0) == 0 else { return nil }
                guard kinfo.kp_eproc.e_ucred.cr_uid == currentUID else { return nil }
                return ProcessEntry(id: pid, pid: pid, cpu: cpu, mem: mem, command: command)
            }
            .sorted { $0.cpu > $1.cpu }
            .prefix(50)
            .map { $0 }
    }
}
