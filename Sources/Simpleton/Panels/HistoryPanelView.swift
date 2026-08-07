import AppKit
// Sources/Simpleton/Panels/HistoryPanelView.swift
import SwiftUI

struct HistoryPanelView: View {
    @ObservedObject private var themeSettings = ThemeSettings.shared

    let shellProvider: () -> String
    let onInsert: (String) -> Void

    @State private var entries: [String] = []
    @State private var query = ""

    private var filtered: [String] {
        query.isEmpty ? entries : entries.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Filter history…", text: $query)
                .textFieldStyle(.plain)
                .foregroundColor(DT.textPrimary)
                .padding(8)
            ThemedDivider()
            if entries.isEmpty {
                PanelEmptyStateView(
                    icon: "clock",
                    title: "No history",
                    message: "History will appear here once your shell has run commands."
                )
            } else {
                List(filtered, id: \.self) { entry in
                    Text(entry)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(DT.textSecondary)
                        .lineLimit(1)
                        .listRowBackground(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { onInsert(entry) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .themedGlass(DT.surface)
        .onAppear { loadHistory() }
    }

    private func loadHistory() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let shellName = URL(fileURLWithPath: shellProvider()).lastPathComponent
        let historyURL: URL
        if shellName.contains("zsh") {
            historyURL = home.appendingPathComponent(".zsh_history")
        } else {
            historyURL = home.appendingPathComponent(".bash_history")
        }
        guard let data = try? Data(contentsOf: historyURL),
            let raw = String(data: data, encoding: .utf8)
        else { return }
        let lines = raw.components(separatedBy: "\n")
            .compactMap { line -> String? in
                let stripped: String
                if line.hasPrefix(": ") {
                    if let semicolonIdx = line.firstIndex(of: ";") {
                        stripped = String(line[line.index(after: semicolonIdx)...])
                    } else {
                        return nil
                    }
                } else {
                    stripped = line
                }
                let trimmed = stripped.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? nil : trimmed
            }
        var seen = Set<String>()
        let unique = lines.filter { seen.insert($0).inserted }
        entries = unique.reversed()
    }
}
