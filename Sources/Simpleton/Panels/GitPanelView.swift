import AppKit
// Sources/Simpleton/Panels/GitPanelView.swift
import SwiftUI

struct GitStatus {
    var branch: String = ""
    var stagedCount: Int = 0
    var unstagedCount: Int = 0
    var commits: [String] = []
}

enum GitPanelState {
    case loading
    case notInstalled
    case notARepo
    case loaded(GitStatus)
}

struct GitPanelView: View {
    let currentPaneProvider: () -> PaneController?

    @ObservedObject private var themeSettings = ThemeSettings.shared
    @State private var state: GitPanelState = .loading

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("GIT")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(DT.textMuted)
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
                    icon: "xmark.circle",
                    title: "Git not found",
                    message: "Install Git to use this panel.",
                    actionLabel: "Get Git",
                    action: { NSWorkspace.shared.open(URL(string: "https://git-scm.com")!) }
                )
            case .notARepo:
                PanelEmptyStateView(
                    icon: "folder.badge.questionmark",
                    title: "Not a git repository",
                    message: "Open a directory that is tracked by git."
                )
            case .loaded(let status):
                gitContent(status)
            }
        }
        .themedGlass(DT.surface)
        .onAppear { Task { await refresh() } }
    }

    @ViewBuilder
    private func gitContent(_ status: GitStatus) -> some View {
        List {
            Section {
                HStack {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundColor(DT.textSecondary)
                    Text(status.branch)
                        .font(DT.monoFont(size: 11))
                        .fontWeight(.semibold)
                        .foregroundColor(DT.textPrimary)
                }
                .listRowBackground(Color.clear)
                HStack(spacing: 16) {
                    Label("\(status.stagedCount) staged", systemImage: "plus.circle.fill")
                        .font(.caption)
                        .foregroundColor(DT.accentGreen)
                    Label("\(status.unstagedCount) unstaged", systemImage: "pencil.circle.fill")
                        .font(.caption)
                        .foregroundColor(DT.accentAmber)
                }
                .listRowBackground(Color.clear)
            } header: {
                Text("STATUS")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(DT.textMuted)
            }
            if !status.commits.isEmpty {
                Section {
                    ForEach(status.commits, id: \.self) { commit in
                        Text(commit)
                            .font(DT.monoFont(size: 10))
                            .foregroundColor(DT.textSecondary)
                            .lineLimit(1)
                            .listRowBackground(Color.clear)
                    }
                } header: {
                    Text("RECENT COMMITS")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.5)
                        .foregroundColor(DT.textMuted)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    @MainActor
    private func refresh() async {
        let cwd = currentPaneProvider()?.currentDirectory ?? FileManager.default.currentDirectoryPath
        state = .loading
        state = await loadGitStatus(cwd: cwd)
    }

    private func loadGitStatus(cwd: String) async -> GitPanelState {
        guard let gitPath = findGit() else { return .notInstalled }
        let rootResult = await runCommand(gitPath, args: ["rev-parse", "--show-toplevel"], cwd: cwd)
        guard rootResult.exitCode == 0 else { return .notARepo }
        let branchResult = await runCommand(gitPath, args: ["rev-parse", "--abbrev-ref", "HEAD"], cwd: cwd)
        let branch = branchResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let statusResult = await runCommand(gitPath, args: ["status", "--short"], cwd: cwd)
        let statusLines = statusResult.output.components(separatedBy: "\n").filter { !$0.isEmpty }
        let staged = statusLines.filter { line in
            guard !line.isEmpty else { return false }
            let x = line[line.startIndex]
            return x != " " && x != "?" && x != "!"
        }.count
        let unstaged = statusLines.filter { line in
            guard line.count >= 2 else { return false }
            let y = line[line.index(after: line.startIndex)]
            return y != " "
        }.count
        let logResult = await runCommand(gitPath, args: ["log", "--oneline", "-10"], cwd: cwd)
        let commits = logResult.output.components(separatedBy: "\n").filter { !$0.isEmpty }
        return .loaded(
            GitStatus(
                branch: branch.isEmpty ? "HEAD" : branch,
                stagedCount: staged,
                unstagedCount: unstaged,
                commits: commits
            ))
    }

    private func findGit() -> String? {
        for path in ["/usr/bin/git", "/usr/local/bin/git", "/opt/homebrew/bin/git"] {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    private func runCommand(
        _ executable: String, args: [String], cwd: String
    ) async -> (output: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ("", 1)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "", process.terminationStatus)
    }
}
