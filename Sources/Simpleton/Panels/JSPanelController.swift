// Sources/Simpleton/Panels/JSPanelController.swift
import AppKit
import WebKit
import SimpletonCore

final class JSPanelDefinition: PanelDefinition {
    let id: String
    let name: String
    let icon: String
    let defaultSide: PanelSide
    let isBuiltIn = false
    let description: String
    private let htmlURL: URL

    init(manifest: ScriptPluginPanelManifest, htmlURL: URL) {
        self.id = manifest.id
        self.name = manifest.name
        self.icon = manifest.icon
        self.defaultSide = manifest.defaultSide
        self.description = manifest.name
        self.htmlURL = htmlURL
    }

    func makeViewController(context: PanelContext) -> NSViewController {
        JSPanelController(id: id, htmlURL: htmlURL, context: context)
    }
}

final class JSPanelController: NSViewController {
    private let panelID: String
    private let htmlURL: URL
    private let context: PanelContext
    private var webView: WKWebView!
    private var bridge: PanelBridge!

    init(id: String, htmlURL: URL, context: PanelContext) {
        self.panelID = id
        self.htmlURL = htmlURL
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        bridge = PanelBridge(panelID: panelID, context: context)
        let config = WKWebViewConfiguration()
        bridge.install(into: config.userContentController)
        webView = WKWebView(frame: .zero, configuration: config)
        bridge.webView = webView
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let parentDir = htmlURL.deletingLastPathComponent()
        webView.loadFileURL(htmlURL, allowingReadAccessTo: parentDir)
    }
}
