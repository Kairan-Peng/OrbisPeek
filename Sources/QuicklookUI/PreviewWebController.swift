// Derived from FreeLook's WKWebView preview integration, MIT License.
// Copyright (c) 2026 Neo Lee. See third-party/FreeLook-LICENSE.md.
import AppKit
import Foundation
import QuicklookCore
import WebKit
#if DEBUG
import os
#endif

@MainActor
open class PreviewWebController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler {
    public var onRender: ((Result<[String: Any], Error>) -> Void)?
    public private(set) var payload: PreviewPayload?
    private let resources = PreviewResourceHandler()
    private var currentRequest = UUID()
    private var activeNavigation: WKNavigation?
    private var commandState = PreviewCommandState()
    private var navigationState = PreviewNavigationState()
    private var resumeState = PreviewResumeState()
    private var loadPolicy = PreviewLoadPolicy.standard
    private var pendingShellNavigation = false
    private var pendingChildNavigation: URL?
    private var directoryScope: DirectoryAccessScope?
    private var scopedURL: URL?
    private var didStartScope = false
    private var windowCloseObserver: NSObjectProtocol?
    private let spinner = NSProgressIndicator()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private static let shellURL = HTMLPreviewDocument.shellURL

    public private(set) lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(resources, forURLScheme: "quicklook-app")
        configuration.setURLSchemeHandler(resources, forURLScheme: "quicklook-resource")
        // A weak proxy avoids the WKUserContentController retaining this controller.
        configuration.userContentController.add(WeakMessageHandler(self), name: "quicklook")
        configuration.userContentController.add(WeakMessageHandler(self), name: "quicklookState")
        configuration.userContentController.addScriptMessageHandler(WeakHTMLMessageHandler(self), contentWorld: .page, name: "quicklookHTML")
        let view = PreviewWebView(frame: .zero, configuration: configuration)
        view.commandState = { [weak self] in self?.commandState ?? PreviewCommandState() }
        view.runCommand = { [weak self] command in self?.performPreviewCommand(command) }
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
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.isHidden = true
        errorLabel.font = .systemFont(ofSize: 15)
        errorLabel.textColor = .secondaryLabelColor
        view.addSubview(errorLabel)
        NSLayoutConstraint.activate([
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            errorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        preferredContentSize = NSSize(width: 920, height: 700)
    }

    public func showFile(_ url: URL, policy: PreviewLoadPolicy = .standard) async throws {
        try await loadFile(url, policy: policy, isResuming: false)
    }

    private func loadFile(_ url: URL, policy: PreviewLoadPolicy, isResuming: Bool) async throws {
        resumeState.invalidate()
        loadPolicy = policy
        let request = UUID()
        currentRequest = request
        navigationState.begin(requestID: request)
        commandState.reset(requestID: request)
        pendingShellNavigation = false
        pendingChildNavigation = nil
        activeNavigation = nil
        payload = nil
        // Revoke old document and image capabilities before asynchronous loading.
        resources.beginRequest(request, documentURL: url)
        loadViewIfNeeded()
        errorLabel.isHidden = true
        webView.isHidden = false
        webView.stopLoading()
        releaseScope()
        directoryScope = DirectoryAccess.activate(for: url)
        scopedURL = url
        didStartScope = url.startAccessingSecurityScopedResource()
        spinner.startAnimation(nil)
        do {
            let prepared = try await Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                if policy == .unclassifiedText, !PreviewPreferences.unclassifiedTextEnabled {
                    throw CocoaError(.fileReadUnknown)
                }
                return try PreviewPayload.load(url: url, decodingPolicy: policy.decodingPolicy,
                                               forcePlainText: policy.forcePlainText)
            }.value
            try Task.checkCancellation()
            guard currentRequest == request else { throw CancellationError() }
            payload = prepared
            pendingShellNavigation = true
            activeNavigation = webView.load(URLRequest(url: Self.shellURL))
        } catch {
            guard currentRequest == request else { throw error }
            resumeState.invalidate()
            navigationState.invalidate()
            commandState.reset()
            resources.invalidate()
            releaseScope()
            spinner.stopAnimation(nil)
            if policy.showsLoadFailure { showFailure(error) }
            else {
                webView.isHidden = true
                if isResuming {
                    errorLabel.stringValue = "无法恢复预览。请关闭后重新按空格预览。"
                    errorLabel.isHidden = false
                }
            }
            throw error
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === activeNavigation, webView.url == Self.shellURL, let payload else { return }
        let request = currentRequest
        Task { @MainActor in
            guard currentRequest == request, navigation === activeNavigation, webView.url == Self.shellURL else { return }
            do {
                var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as! [String: Any]
                object["resourceToken"] = resources.resourceToken()
                let options: [String: Any] = [:]
                let result = try await webView.callAsyncJavaScript(
                    "return window.quicklook.render(payload, requestID, options)",
                    arguments: ["payload": object, "requestID": request.uuidString, "options": options], in: nil, contentWorld: .page
                )
                guard currentRequest == request, navigation === activeNavigation,
                      webView.url == Self.shellURL, self.payload != nil,
                      (result as? [String: Any])?["stale"] as? Bool != true else { return }
                navigationState.didRender(requestID: request)
                spinner.stopAnimation(nil)
                onRender?(.success(result as? [String: Any] ?? [:]))
            } catch {
                guard currentRequest == request else { return }
                failCurrentNavigation(error)
            }
        }
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard navigation === activeNavigation else { return }
        failCurrentNavigation(error)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard navigation === activeNavigation else { return }
        failCurrentNavigation(error)
    }

    private func failCurrentNavigation(_ error: Error) {
        navigationState.invalidate()
        resumeState.invalidate()
        activeNavigation = nil
        payload = nil
        commandState.reset()
        pendingShellNavigation = false
        pendingChildNavigation = nil
        resources.invalidate()
        releaseScope()
        spinner.stopAnimation(nil)
        showFailure(error)
        onRender?(.failure(error))
    }

    private func showFailure(_ error: Error) {
        // Error UI stays native; the navigation gate admits no about:blank or
        // arbitrary HTML load as an exception to the shell/child boundary.
        webView.isHidden = true
        errorLabel.stringValue = "Cannot preview this file\n\(error.localizedDescription)"
        errorLabel.isHidden = false
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, let target = navigationAction.targetFrame, target.webView === webView else { decisionHandler(.cancel); return }
        // Native initial loads have no source document (and may expose a nil
        // Objective-C request despite WKFrameInfo's nonoptional Swift import).
        if target.isMainFrame, pendingShellNavigation, url == Self.shellURL, navigationAction.navigationType == .other {
            pendingShellNavigation = false
            decisionHandler(.allow)
            return
        }
        guard navigationAction.sourceFrame.webView === webView else { decisionHandler(.cancel); return }
        let source = navigationAction.sourceFrame
        let sourceIsShell = source.isMainFrame && source.request.url == Self.shellURL
        let sourceIsChild = !source.isMainFrame && source.request.url.map(isCurrentChildLocation) == true
        if navigationAction.navigationType == .linkActivated {
            if navigationState.allowsUserNavigation(requestID: currentRequest, trustedSource: sourceIsShell || sourceIsChild) {
                if ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                    NSWorkspace.shared.open(url)
                } else if sourceIsChild, !target.isMainFrame, url.fragment != nil, isCurrentChildLocation(url) {
                    decisionHandler(.allow)
                    return
                }
            }
            decisionHandler(.cancel)
            return
        }
        guard navigationAction.navigationType == .other else { decisionHandler(.cancel); return }
        if !target.isMainFrame, pendingChildNavigation == url, resources.isCurrentDocument(url) {
            pendingChildNavigation = nil
            decisionHandler(.allow)
        } else { decisionHandler(.cancel) }
    }

    private func isCurrentChildLocation(_ url: URL) -> Bool {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false), components.query == nil else { return false }
        components.fragment = nil
        return components.url.map(resources.isCurrentDocument) == true
    }

    private func trustedRequestBody(_ message: WKScriptMessage) -> [String: Any]? {
        guard message.frameInfo.isMainFrame,
              message.frameInfo.request.url == Self.shellURL,
              message.webView === webView, webView.url == Self.shellURL,
              payload != nil,
              let body = message.body as? [String: Any],
              let requestID = body["requestID"] as? String, UUID(uuidString: requestID) == currentRequest else { return nil }
        return body
    }

    fileprivate func receiveHTMLRequest(_ message: WKScriptMessage, reply: @escaping (Any?, String?) -> Void) {
        guard let body = trustedRequestBody(message) else {
            reply(["ok": false, "error": "untrusted-or-stale-request"], nil)
            return
        }
        guard body["action"] as? String == "prepareHTML", let html = body["html"] as? String else {
            resources.discardPreparedHTML(requestID: currentRequest)
            reply(["ok": false, "error": "invalid-preparation"], nil)
            return
        }
        do {
            let url = try resources.prepareHTML(html, requestID: currentRequest)
            pendingChildNavigation = url
            reply(["ok": true, "url": url.absoluteString], nil)
        } catch {
            reply(["ok": false, "error": "preparation-rejected"], nil)
        }
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = trustedRequestBody(message) else { return }
        if message.name == "quicklookState", body["action"] as? String == "commandState" {
            commandState.receive(body, currentRequest: currentRequest)
            return
        }
        if message.name == "quicklookState", body["action"] as? String == "openImageAccess" {
            guard commandState.allowsImageAccessRequest(body, currentRequest: currentRequest),
                  navigationState.allowsUserNavigation(requestID: currentRequest, trustedSource: true),
                  payload?.mode == "markdown" || payload?.mode == "html" else { return }
            // This fixed destination opens the host's management page. Only its
            // native folder picker can grant access; authored links stay blocked.
            openImageAccess(request: currentRequest, generation: commandState.generation)
            return
        }
        guard message.name == "quicklook", body["action"] as? String == "copy",
              let generation = body["viewGeneration"] as? Int, generation == commandState.generation,
              let text = body["text"] as? String, text.utf8.count <= 4 * 1024 * 1024 else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func openImageAccess(request: UUID, generation: Int) {
        Task { @MainActor in
            guard currentRequest == request, commandState.hasBody,
                  commandState.generation == generation else { return }
            let allowed = try? await webView.callAsyncJavaScript(
                "return window.quicklook.canOpenImageAccess(requestID, generation)",
                arguments: ["requestID": request.uuidString, "generation": generation], in: nil, contentWorld: .page
            ) as? Bool
            guard allowed == true, currentRequest == request, commandState.hasBody,
                  commandState.generation == generation,
                  navigationState.allowsUserNavigation(requestID: request, trustedSource: true) else { return }
#if DEBUG
            let logger = Logger(subsystem: "org.quicklook.preview", category: "ImageAccess")
#endif
            if let context = extensionContext {
                // The hosting app opens the fixed route on the extension's
                // behalf; Quick Look may not launch across sessions directly.
                context.open(ImageAccessRoute.url) { [weak self] opened in
#if DEBUG
                    logger.notice("contextOpen completed success=\(opened, privacy: .public)")
#endif
                    if !opened {
                        Task { @MainActor [weak self] in
                            await self?.showImageAccessOpenFailure(request: request, generation: generation)
                        }
                    }
                }
                return
            }
            guard let application = HostImageAccessTarget.applicationURL(for: Bundle.main.bundleURL) else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([ImageAccessRoute.url], withApplicationAt: application, configuration: configuration) { [weak self] running, error in
#if DEBUG
                if let error {
                    let native = error as NSError
                    logger.error("hostOpen failed domain=\(native.domain, privacy: .public) code=\(native.code, privacy: .public)")
                } else {
                    let exactTarget = running?.bundleURL?.standardizedFileURL.path == application.standardizedFileURL.path
                    logger.notice("hostOpen completed pid=\(running?.processIdentifier ?? -1, privacy: .public) exactTarget=\(exactTarget, privacy: .public)")
                }
#endif
                if error != nil {
                    Task { @MainActor [weak self] in
                        await self?.showImageAccessOpenFailure(request: request, generation: generation)
                    }
                }
            }
        }
    }

    private func showImageAccessOpenFailure(request: UUID, generation: Int) async {
        guard currentRequest == request, commandState.hasBody, commandState.generation == generation,
              navigationState.allowsUserNavigation(requestID: request, trustedSource: true) else { return }
        _ = try? await webView.callAsyncJavaScript(
            "return window.quicklook.imageAccessOpenFailed(requestID, generation)",
            arguments: ["requestID": request.uuidString, "generation": generation], in: nil, contentWorld: .page
        )
    }

    /// Standard responder/keyboard actions are request and view-generation scoped.
    public func performPreviewCommand(_ command: String) {
        guard ["copy", "selectAll"].contains(command), payload != nil,
              commandState.requestID == currentRequest, commandState.generation >= 0 else { return }
        let request = currentRequest
        let generation = commandState.generation
        Task { @MainActor in
            guard currentRequest == request, commandState.generation == generation else { return }
            do {
                let result = try await webView.callAsyncJavaScript(
                    "return window.quicklook.commands.executeNative(command, requestID, generation)",
                    arguments: ["command": command, "requestID": request.uuidString, "generation": generation], in: nil, contentWorld: .page
                ) as? [String: Any]
                guard currentRequest == request else { return }
                guard commandState.generation == generation, let result else { return }
                commandState.receive(result, currentRequest: request)
                guard result["stateSequence"] as? Int == commandState.sequence else { return }
                // Focus may move to an editor between synchronous action lookup
                // and this DOM check. Dispatch its standard WebKit action; no JS
                // clipboard or selection emulation is used for the editor.
                if result["handled"] as? Bool == false, commandState.editorFocused {
                    if command == "copy" { NSApp.sendAction(#selector(NSText.copy(_:)), to: webView, from: self) }
                    else if command == "selectAll" { NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: webView, from: self) }
                    return
                }
                guard result["handled"] as? Bool == true, command == "copy",
                      let text = result["text"] as? String, text.utf8.count <= 4 * 1024 * 1024 else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } catch {
                // A replaced or closed document cannot complete an action.
            }
        }
    }

    public func resourceDiagnostics() -> [[String: String]] { resources.diagnostics() }

    /// Also usable by hosts that remove a preview without a view lifecycle transition.
    public func invalidatePreview() {
        navigationState.invalidate()
        resumeState.invalidate()
        currentRequest = UUID()
        commandState.reset()
        pendingShellNavigation = false
        pendingChildNavigation = nil
        activeNavigation = nil
        payload = nil
        loadPolicy = .standard
        resources.invalidate()
        if isViewLoaded { webView.stopLoading() }
        spinner.stopAnimation(nil)
        releaseScope()
    }

    open override func viewDidDisappear() {
        super.viewDidDisappear()
        let file = scopedURL
        let policy = loadPolicy
        invalidatePreview()
        resumeState.suspend(file, policy: policy)
    }

    open override func viewDidAppear() {
        super.viewDidAppear()
        if let windowCloseObserver { NotificationCenter.default.removeObserver(windowCloseObserver) }
        guard let window = view.window else { return }
        windowCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                guard let self, let window, self.view.window === window else { return }
                self.invalidatePreview()
            }
        }
        if let ticket = resumeState.ticket {
            Task { @MainActor [weak self, weak window] in
                await Task.yield()
                guard let self, let window, self.view.window === window,
                      window.isVisible, !window.isMiniaturized,
                      let file = self.resumeState.consume(ticket) else { return }
                // New capabilities are issued; preview mode/query reset to the
                // normal new-document defaults on this bounded reload.
                try? await self.loadFile(file, policy: ticket.policy, isResuming: true)
            }
        }
    }

    private func releaseScope() {
        directoryScope = nil
        if didStartScope { scopedURL?.stopAccessingSecurityScopedResource() }
        scopedURL = nil
        didStartScope = false
    }

    deinit {
        if let windowCloseObserver { NotificationCenter.default.removeObserver(windowCloseObserver) }
        resources.invalidate()
        if didStartScope { scopedURL?.stopAccessingSecurityScopedResource() }
    }
}

@MainActor
private final class WeakHTMLMessageHandler: NSObject, WKScriptMessageHandlerWithReply {
    weak var target: PreviewWebController?
    init(_ target: PreviewWebController) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let target else { replyHandler(["ok": false, "error": "preview-closed"], nil); return }
        target.receiveHTMLRequest(message, reply: replyHandler)
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
