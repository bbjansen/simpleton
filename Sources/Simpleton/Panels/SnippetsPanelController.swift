// Sources/Simpleton/Panels/SnippetsPanelController.swift
import AppKit
import SwiftUI
import SimpletonCore

final class SnippetsPanelController: NSViewController {
    private let context: PanelContext
    private let store: SnippetStore

    init(context: PanelContext) {
        self.context = context
        self.store = SnippetStore(appSupportDir: context.appSupportDir)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let v = SnippetsPanelView(store: store, onInsert: context.onInsertCommand)
        self.view = NSHostingView(rootView: v)
        self.view.frame = NSRect(x: 0, y: 0, width: 240, height: 600)
    }
}

struct SnippetsPanelView: View {
    @ObservedObject var store: SnippetStore
    let onInsert: (String) -> Void

    @State private var query = ""
    @State private var selectedID: UUID?
    @State private var fillValues: [String: String] = [:]
    @State private var isAdding = false
    @State private var newName = ""
    @State private var newCommand = ""

    private var filtered: [Snippet] {
        if query.isEmpty { return store.snippets }
        let q = query.lowercased()
        return store.snippets.filter {
            $0.name.lowercased().contains(q) || $0.command.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search + add
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(.system(size: 11))
                TextField("Search snippets…", text: $query).font(.system(size: 11))
                Button(action: { isAdding.toggle() }) {
                    Image(systemName: "plus").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(8)

            Divider()

            // Add form
            if isAdding {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Name", text: $newName).font(.system(size: 11))
                    TextField("Command (use {param} for placeholders)", text: $newCommand)
                        .font(.system(size: 11, design: .monospaced))
                    HStack {
                        Spacer()
                        Button("Cancel") { isAdding = false; newName = ""; newCommand = "" }
                            .font(.system(size: 11))
                        Button("Add") { addSnippet() }
                            .font(.system(size: 11))
                            .disabled(newName.isEmpty || newCommand.isEmpty)
                    }
                }
                .padding(8)
                .background(Color(nsColor: NSColor(white: 0.1, alpha: 1)))
                Divider()
            }

            // List
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(filtered) { snippet in
                        snippetRow(snippet)
                    }
                    if filtered.isEmpty {
                        Text(store.snippets.isEmpty ? "No snippets yet" : "No results")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                            .padding()
                    }
                }
                .padding(6)
            }

            // Fill form for selected snippet with placeholders
            if let id = selectedID,
               let snippet = store.snippets.first(where: { $0.id == id }) {
                let placeholders = extractPlaceholders(snippet.command)
                if !placeholders.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(placeholders, id: \.self) { ph in
                            HStack {
                                Text(ph)
                                    .font(.system(size: 10))
                                    .foregroundColor(.purple)
                                    .frame(width: 60, alignment: .leading)
                                TextField(ph, text: Binding(
                                    get: { fillValues[ph] ?? "" },
                                    set: { fillValues[ph] = $0 }
                                ))
                                .font(.system(size: 11))
                            }
                        }
                        Button("Insert") {
                            insertFilled(snippet: snippet, placeholders: placeholders)
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(8)
                }
            }
        }
    }

    private func snippetRow(_ snippet: Snippet) -> some View {
        Button(action: { selectSnippet(snippet) }) {
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.name).font(.system(size: 11)).lineLimit(1)
                Text(snippet.command)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(selectedID == snippet.id ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete", role: .destructive) { store.delete(id: snippet.id) }
        }
    }

    private func selectSnippet(_ snippet: Snippet) {
        let placeholders = extractPlaceholders(snippet.command)
        if placeholders.isEmpty {
            onInsert(snippet.command)
        } else {
            selectedID = snippet.id
            fillValues = [:]
        }
    }

    private func insertFilled(snippet: Snippet, placeholders: [String]) {
        var cmd = snippet.command
        for ph in placeholders {
            cmd = cmd.replacingOccurrences(of: "{\(ph)}", with: fillValues[ph] ?? ph)
        }
        onInsert(cmd)
        selectedID = nil
        fillValues = [:]
    }

    private func addSnippet() {
        store.add(Snippet(name: newName, command: newCommand))
        isAdding = false
        newName = ""
        newCommand = ""
    }

    private func extractPlaceholders(_ command: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: #"\{(\w+)\}"#)
        let matches = pattern.matches(in: command, range: NSRange(command.startIndex..., in: command))
        var seen = Set<String>()
        return matches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: command) else { return nil }
            let ph = String(command[range])
            return seen.insert(ph).inserted ? ph : nil
        }
    }
}
