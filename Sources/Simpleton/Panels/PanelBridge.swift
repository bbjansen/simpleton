// Sources/Simpleton/Panels/PanelBridge.swift
import Foundation
import WebKit
import SimpletonCore

final class PanelBridge: NSObject, WKScriptMessageHandler {

    private let panelID: String
    private let context: PanelContext
    weak var webView: WKWebView?
    private var outputObserver: NSObjectProtocol?

    init(panelID: String, context: PanelContext) {
        self.panelID = panelID
        self.context = context
    }

    func install(into controller: WKUserContentController) {
        guard let shimURL = Bundle.main.url(forResource: "panel-bridge", withExtension: "js"),
              let shim = try? String(contentsOf: shimURL, encoding: .utf8) else {
            assertionFailure("panel-bridge.js missing from app bundle")
            return
        }
        controller.addUserScript(WKUserScript(
            source: shim,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        for name in ["insert", "getOutput", "getCwd", "getSelection",
                     "onOutput", "offOutput", "storageGet", "storageSet", "storageGetAll"] {
            controller.add(self, name: name)
        }
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        DispatchQueue.main.async { [weak self] in self?.handle(message: message) }
    }

    private func handle(message: WKScriptMessage) {
        switch message.name {

        case "insert":
            if let cmd = message.body as? String {
                context.onInsertCommand(cmd)
            }

        case "getOutput":
            let n = (message.body as? [String: Any]).flatMap { $0["body"] as? Int } ?? 50
            reply(to: message, value: terminalLastLines(n: n))

        case "getCwd":
            reply(to: message, value: context.currentPane()?.currentDirectory ?? "")

        case "getSelection":
            reply(to: message, value: context.currentPane()?.terminalView.getSelection() ?? "")

        case "onOutput":
            subscribeOutput()

        case "offOutput":
            unsubscribeOutput()

        case "storageGet":
            let key = (message.body as? [String: Any]).flatMap { $0["body"] as? String } ?? ""
            reply(to: message, value: loadStorage()[key] as Any)

        case "storageSet":
            if let body = (message.body as? [String: Any])?["body"] as? [String: Any],
               let key = body["key"] as? String {
                var store = loadStorage()
                store[key] = body["value"]
                saveStorage(store)
            }

        case "storageGetAll":
            reply(to: message, value: loadStorage())

        default:
            break
        }
    }

    // MARK: - Promise Reply

    private func reply(to message: WKScriptMessage, value: Any) {
        guard let callbackId = (message.body as? [String: Any])?["callbackId"] as? String else { return }
        let json: String
        if let data = try? JSONSerialization.data(withJSONObject: value, options: []),
           let str = String(data: data, encoding: .utf8) {
            json = str
        } else if let str = value as? String {
            let escaped = str
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            json = "\"\(escaped)\""
        } else {
            json = "null"
        }
        let js = "window.__resolveCallback(\"\(callbackId)\", \(json));"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Output Subscription

    private func subscribeOutput() {
        guard outputObserver == nil else { return }
        outputObserver = NotificationCenter.default.addObserver(
            forName: .simpletonTerminalOutput, object: nil, queue: .main
        ) { [weak self] notification in
            guard let lines = notification.object as? [String] else { return }
            self?.deliverOutput(lines: lines)
        }
    }

    private func unsubscribeOutput() {
        if let obs = outputObserver {
            NotificationCenter.default.removeObserver(obs)
            outputObserver = nil
        }
    }

    private func deliverOutput(lines: [String]) {
        guard let data = try? JSONSerialization.data(withJSONObject: lines),
              let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.__deliverOutput(\(json));", completionHandler: nil)
    }

    // MARK: - Terminal Helpers

    private func terminalLastLines(n: Int) -> [String] {
        guard let tv = context.currentPane()?.terminalView else { return [] }
        let terminal = tv.getTerminal()
        let totalRows = terminal.rows
        let startRow = max(0, totalRows - n)
        var lines: [String] = []
        for row in startRow..<totalRows {
            if let line = terminal.getLine(row: row) {
                let text = line.translateToString(trimRight: true)
                if !text.isEmpty { lines.append(text) }
            }
        }
        return lines
    }

    // MARK: - Storage

    private var storageFile: URL {
        let dir = context.appSupportDir.appendingPathComponent("panel-storage")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(panelID).json")
    }

    private func loadStorage() -> [String: Any] {
        guard let data = try? Data(contentsOf: storageFile),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    private func saveStorage(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        try? data.write(to: storageFile, options: .atomic)
    }
}
