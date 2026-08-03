// Sources/Simpleton/Panels/JSPanelController.swift
import AppKit
import WebKit
import SimpletonCore

extension PanelDefinition {
    static func jsPanel(manifest: ScriptPluginPanelManifest, htmlURL: URL) -> PanelDefinition {
        PanelDefinition(
            id: manifest.id,
            name: manifest.name,
            icon: manifest.icon,
            description: manifest.name,
            defaultSide: manifest.defaultSide,
            isBuiltIn: false
        ) { context in
            JSPanelController(id: manifest.id, htmlURL: htmlURL, context: context)
        }
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

    override func viewWillAppear() {
        super.viewWillAppear()
        bridge.panelDidBecomeVisible()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        bridge.panelDidBecomeHidden()
    }
}
