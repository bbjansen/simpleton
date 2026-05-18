// Sources/Simpleton/Panels/NotesPanelController.swift
import AppKit
import SwiftUI
import Combine
import SimpletonCore

final class NotesPanelController: NSViewController {
    private let context: PanelContext

    init(context: PanelContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let notesView = NotesPanelView(
            appSupportDir: context.appSupportDir,
            currentPaneProvider: context.currentPane
        )
        let host = NSHostingView(rootView: notesView)
        host.frame = NSRect(x: 0, y: 0, width: 240, height: 600)
        self.view = host
    }
}

struct NotesPanelView: View {
    let appSupportDir: URL
    let currentPaneProvider: () -> PaneController?

    @State private var cwd: String? = nil
    @State private var text = ""
    @State private var savePublisher = PassthroughSubject<String, Never>()
    @State private var saveTimer: AnyCancellable?

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
                    .foregroundColor(.secondary)
                Spacer()
                if let c = cwd {
                    Text(URL(fileURLWithPath: c).lastPathComponent)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            Divider()
            TextEditor(text: $text)
                .font(.system(size: 12, design: .monospaced))
                .onChange(of: text) { newText in
                    savePublisher.send(newText)
                }
        }
        .onAppear {
            setupSaveTimer()
            refreshCwd()
            loadNote()
        }
        // Poll for CWD changes every 2 seconds
        .onReceive(Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()) { _ in
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
        saveTimer = savePublisher
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { newText in
                try? newText.write(to: noteFile, atomically: true, encoding: .utf8)
            }
    }
}
