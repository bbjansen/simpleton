// Sources/Simpleton/Views/AIExplainPanel.swift
import AppKit
import SwiftUI

/// Floating panel that shows an AI explanation (for errors or selected text).
final class AIExplainPanel {

    private var panel: NSPanel?

    func show(title: String, aiService: AIService, system: String, user: String, relativeTo window: NSWindow?) {
        // Hide any currently visible panel first (orderOut, not close)
        panel?.orderOut(nil)

        // Create the panel once and reuse the NSPanel shell; always rebuild content
        // because each invocation has different title/prompt/AI context.
        if panel == nil {
            let newPanel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 450, height: 350),
                styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newPanel.isFloatingPanel = true
            newPanel.level = .floating
            newPanel.titleVisibility = .hidden
            newPanel.titlebarAppearsTransparent = true
            newPanel.backgroundColor = NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    ? NSColor(white: 0.1, alpha: 0.98) : NSColor(white: 0.97, alpha: 0.98)
            }
            newPanel.hasShadow = true
            self.panel = newPanel
        }

        guard let panel = panel else { return }

        // Rebuild content view with fresh prompt/context each time
        let contentView = AIExplainContentView(
            title: title,
            aiService: aiService,
            system: system,
            user: user,
            onDismiss: { [weak self] in self?.dismiss() }
        )
        panel.contentView = NSHostingView(rootView: contentView)

        if let window = window {
            let x = window.frame.midX - 225
            let y = window.frame.midY - 100
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.center()
        }

        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        // orderOut hides the panel without deallocating it, preventing use-after-free
        // in AppKit window animation blocks during close.
        panel?.orderOut(nil)
    }
}

struct AIExplainContentView: View {
    let title: String
    let aiService: AIService
    let system: String
    let user: String
    let onDismiss: () -> Void

    @State private var response = ""
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)

            Divider()

            // Content
            ScrollView {
                if isLoading && response.isEmpty {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Thinking...")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else if let error = error {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .padding()
                } else {
                    Text(makeAttributed(response))
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Footer
            if !response.isEmpty {
                Divider()
                HStack {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(response, forType: .string)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    Spacer()
                }
                .padding(8)
            }
        }
        .frame(width: 450, height: 350)
        .background(DT.surface)
        .onAppear { fetchExplanation() }
    }

    private func fetchExplanation() {
        Task {
            do {
                let stream = aiService.stream(system: system, user: user)
                for try await token in stream {
                    response += token
                }
                isLoading = false
            } catch {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func makeAttributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}
