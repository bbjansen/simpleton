import Combine
// Sources/Simpleton/Panels/SnippetStore.swift
import Foundation
import SimpletonCore

final class SnippetStore: ObservableObject {
    @Published private(set) var snippets: [Snippet] = []
    private let file: URL

    init(appSupportDir: URL) {
        self.file = appSupportDir.appendingPathComponent("snippets.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: file) else { return }
        snippets = (try? JSONDecoder().decode([Snippet].self, from: data)) ?? []
    }

    func add(_ snippet: Snippet) {
        snippets.append(snippet)
        save()
    }

    func update(_ snippet: Snippet) {
        guard let idx = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        snippets[idx] = snippet
        save()
    }

    func delete(id: UUID) {
        snippets.removeAll { $0.id == id }
        save()
    }

    private func save() {
        try? AtomicFileWriter.writeJSON(snippets, to: file)
    }
}
