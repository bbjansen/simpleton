import Combine
import SimpletonCore
// Sources/Simpleton/Panels/NotesPanelController.swift
import SwiftUI

struct NotesPanelView: View {
    @ObservedObject private var themeSettings = ThemeSettings.shared

    let appSupportDir: URL
    let currentPaneProvider: () -> PaneController?

    @State private var cwd: String? = nil
    @State private var text = ""
    // The save publisher carries the destination file captured at type time, so a
    // debounced write always lands in the note that was current when the text changed,
    // even if the cwd changes within the debounce window.
    @State private var savePublisher = PassthroughSubject<(url: URL, text: String), Never>()
    @State private var saveTimer: AnyCancellable?

    // Poll CWD changes with a single long-lived timer instead of recreating one on
    // every body render.
    private let cwdTimer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()

    private var notesDir: URL { appSupportDir.appendingPathComponent("notes") }

    private var noteKey: String {
        let raw = cwd ?? "global"
        return raw.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private var noteFile: URL { notesDir.appendingPathComponent(noteKey + ".md") }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Notes")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DT.textMuted)
                Spacer()
                if let c = cwd {
                    Text(URL(fileURLWithPath: c).lastPathComponent)
                        .font(.system(size: 10))
                        .foregroundColor(DT.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            ThemedDivider()
            TextEditor(text: $text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(DT.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 4)
                .padding(.top, 4)
                .onChange(of: text) { newText in
                    savePublisher.send((url: noteFile, text: newText))
                }
        }
        .themedGlass(DT.surface)
        .onAppear {
            setupSaveTimer()
            refreshCwd()
            loadNote()
        }
        // Poll for CWD changes every 2 seconds
        .onReceive(cwdTimer) { _ in
            let newCwd = currentPaneProvider()?.currentDirectory
            if newCwd != cwd {
                cwd = newCwd
                loadNote()
            }
        }
    }

    private func refreshCwd() {
        cwd = currentPaneProvider()?.currentDirectory
    }

    private func loadNote() {
        try? FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)
        text = (try? String(contentsOf: noteFile, encoding: .utf8)) ?? ""
    }

    private func setupSaveTimer() {
        saveTimer =
            savePublisher
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { payload in
                try? payload.text.write(to: payload.url, atomically: true, encoding: .utf8)
            }
    }
}
