// Derived from FreeLook's WKWebView preview integration, MIT License.
// Copyright (c) 2026 Neo Lee. See third-party/FreeLook-LICENSE.md.
import AppKit
import Foundation
import QuicklookCore
import WebKit

@MainActor
open class PreviewWebController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler {
    public var onRender: ((Result<[String: Any], Error>) -> Void)?
    public private(set) var payload: PreviewPayload?
    private let resources = PreviewResourceHandler()
    private var currentRequest = UUID()
    private var activeNavigation: WKNavigation?
    private var directoryScope: DirectoryAccessScope?
    private var scopedURL: URL?
    private var didStartScope = false
    private let spinner = NSProgressIndicator()

    public private(set) lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(resources, forURLScheme: "quicklook-app")
        configuration.setURLSchemeHandler(resources, forURLScheme: "quicklook-resource")
        // A weak proxy avoids the WKUserContentController retaining this controller.
        configuration.userContentController.add(WeakMessageHandler(self), name: "quicklook")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.navigationDelegate = self
        view.underPageBackgroundColor = .textBackgroundColor
        return view
    }()

    open override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        view.addSubview(webView)
        spinner.style = .spinning
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isDisplayedWhenStopped = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        preferredContentSize = NSSize(width: 920, height: 700)
    }

    public func showFile(_ url: URL) async throws {
        loadViewIfNeeded()
        let request = UUID()
        currentRequest = request
        activeNavigation = nil
        payload = nil
        releaseScope()
        directoryScope = DirectoryAccess.activate(for: url)
        scopedURL = url
        didStartScope = url.startAccessingSecurityScopedResource()
        spinner.startAnimation(nil)
        do {
            let prepared = try await Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                return try PreviewPayload.load(url: url)
            }.value
            try Task.checkCancellation()
            guard currentRequest == request else { throw CancellationError() }
            payload = prepared
            resources.setDocument(url)
            activeNavigation = webView.load(URLRequest(url: URL(string: "quicklook-app://bundle/index.html")!))
        } catch {
            guard currentRequest == request else { throw error }
            spinner.stopAnimation(nil)
            let message = error.localizedDescription
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
            webView.loadHTMLString("<meta charset='utf-8'><style>body{font:16px system-ui;padding:32px;color:CanvasText;background:Canvas;color-scheme:light dark}</style><h2>Cannot preview this file</h2><p>\(message)</p>", baseURL: nil)
            throw error
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === activeNavigation, webView.url?.scheme == "quicklook-app", let payload else { return }
        let request = currentRequest
        Task { @MainActor in
            do {
                let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload))
                let result = try await webView.callAsyncJavaScript(
                    "return window.quicklook.render(payload)",
                    arguments: ["payload": object], in: nil, contentWorld: .page
                )
                guard currentRequest == request else { return }
                spinner.stopAnimation(nil)
                onRender?(.success(result as? [String: Any] ?? [:]))
            } catch {
                guard currentRequest == request else { return }
                spinner.stopAnimation(nil)
                onRender?(.failure(error))
            }
        }
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard navigation === activeNavigation else { return }
        spinner.stopAnimation(nil)
        onRender?(.failure(error))
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if navigationAction.navigationType == .linkActivated {
            // Users can explicitly open external links in their browser; documents never navigate the preview.
            if ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(url.scheme == "quicklook-app" || url.absoluteString == "about:blank" ? .allow : .cancel)
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              message.frameInfo.request.url?.scheme == "quicklook-app",
              let body = message.body as? [String: Any], body["action"] as? String == "copy",
              let text = body["text"] as? String, text.utf8.count <= 4 * 1024 * 1024 else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    public func resourceDiagnostics() -> [[String: String]] { resources.diagnostics() }

    private func releaseScope() {
        directoryScope = nil
        if didStartScope { scopedURL?.stopAccessingSecurityScopedResource() }
        scopedURL = nil
        didStartScope = false
    }

    deinit {
        if didStartScope { scopedURL?.stopAccessingSecurityScopedResource() }
    }
}

@MainActor
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
