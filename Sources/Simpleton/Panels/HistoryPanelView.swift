import AppKit
// Sources/Simpleton/Panels/HistoryPanelView.swift
import SwiftUI

struct HistoryPanelView: View {
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
                .padding(8)
            Divider()
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
                        .lineLimit(1)
                        .contentShape(Rectangle())
                        .onTapGesture { onInsert(entry) }
                }
                .listStyle(.plain)
            }
        }
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
