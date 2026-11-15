import AppKit
import Foundation
import QuicklookCore
import QuicklookUI
import UniformTypeIdentifiers
import WebKit

/// Offscreen probe-only target lookup. This never activates an application or
/// proves actual keyboard delivery in Finder's Quick Look host.
@MainActor
final class ProbeApplication: NSApplication {
    weak var routingWindow: NSWindow?
    override var keyWindow: NSWindow? { routingWindow ?? super.keyWindow }
    override var mainWindow: NSWindow? { routingWindow ?? super.mainWindow }
}

@MainActor
final class RenderProbe: NSObject, WKScriptMessageHandler {
    let controller = PreviewWebController()
    let window: NSWindow
    let output: URL?
    let snapshot: URL?
    let checks: String?
    let loopbackOrigin: String?
    var childFrame: WKFrameInfo?
    let start = CFAbsoluteTimeGetCurrent()
    var finished = false
    var isCapturing = false
    var renderCount = 0
    var latestRender: [String: Any] = [:]
    let fileURL: URL

    init(url: URL, output: URL?, snapshot: URL?, checks: String?, loopbackOrigin: String?) {
        self.fileURL = url
        self.output = output
        self.snapshot = snapshot
        self.checks = checks
        self.loopbackOrigin = loopbackOrigin
        window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 1000, height: 760), styleMask: [.titled, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        if checks == "html-container" || checks == "html-static" || checks == "no-find" || checks == "markdown-images" || checks == "image-access" || checks == "line-selection" {
            let content = controller.webView.configuration.userContentController
            content.addUserScript(WKUserScript(source: """
                const render = window.quicklook.render;
                window.quicklook.render = function(payload, requestID, options) {
                  window.__containerProbe = {requestID, resourceToken:payload.resourceToken,payload};
                  if(\(checks == "html-static" ? "true" : "false")) payload={...payload,mode:'html',language:'html',text:payload.text.replaceAll('https://example.invalid',\(loopbackOrigin.map { "\"\($0)\"" } ?? "'https://example.invalid'"))};
                  return render(payload, requestID, options);
                };
                """, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .page))
            content.add(self, contentWorld: .defaultClient, name: "containerProbeFrame")
            content.addUserScript(WKUserScript(source: "window.webkit.messageHandlers.containerProbeFrame.postMessage({});", injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: .defaultClient))
        }
        window.contentViewController = controller
        window.orderBack(nil)
        if checks == "html-static" { (NSApp as? ProbeApplication)?.routingWindow = window; window.makeFirstResponder(controller.webView) }
        controller.onRender = { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let metadata):
                self.renderCount += 1
                self.latestRender = metadata
                if !self.isCapturing { Task { await self.capture(metadata: metadata) } }
            case .failure(let error): self.complete(["error": error.localizedDescription], status: 1)
            }
        }
        Task {
            do { try await controller.showFile(url) }
            catch { complete(["error": error.localizedDescription], status: 1) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            self?.complete(["error": "WKWebView render timed out"], status: 1)
        }
    }

    func capture(metadata: [String: Any]) async {
        isCapturing = true
        do {
            let interactions = checks == "html-container" ? try await HTMLContainerChecks.run(probe: self, loopbackOrigin: loopbackOrigin) : nil
            let staticHTML = checks == "html-static" ? try await HTMLStaticChecks.run(probe: self) : nil
            let noFind = checks == "no-find" ? try await NoFindChecks.run(probe: self) : nil
            let nativeCopy = checks == "native-copy" ? try await NativeCopyChecks.run(probe: self) : nil
            let markdownImages = checks == "markdown-images" ? try await MarkdownImageChecks.run(probe: self) : nil
            let imageAccess = checks == "image-access" ? try await ImageAccessPromptChecks.run(probe: self) : nil
            let lineSelection = checks == "line-selection" ? try await LineNumberSelectionChecks.run(probe: self) : nil
            let metrics = try await controller.webView.callAsyncJavaScript("""
                const body=window.quicklook.getBodyView(),active=body?.document??document,root=body?.root??document.body;
                const deadline=Date.now()+2000;
                while(Array.from(active.images).some(img=>!img.complete)&&Date.now()<deadline)await new Promise(resolve=>setTimeout(resolve,30));
                return {
                  title: document.title,
                  text: root.innerText.slice(0, 2000),
                  bodyKind:body?.kind??null, activeDocumentURL:active.URL,
                  images: Array.from(active.images).map(img => ({src:img.getAttribute('src'),loaded:img.naturalWidth>0,
                    alt:img.alt,width:img.getBoundingClientRect().width,height:img.getBoundingClientRect().height,
                    naturalWidth:img.naturalWidth,naturalHeight:img.naturalHeight})),
                  scripts: document.scripts.length,
                  trustedParentScripts:document.scripts.length,childScripts:active===document?null:active.scripts.length,
                  untrustedParentScriptRan:!!window.quicklookFixtureScriptExecuted,
                  untrustedChildScriptRan:active===document?false:!!active.defaultView.quicklookFixtureScriptExecuted,
                  scrollWidth: document.documentElement.scrollWidth,
                  viewportWidth: window.innerWidth
                };
                """, arguments: [:], in: nil, contentWorld: .page)
            if let snapshot {
                let image = try await controller.webView.takeSnapshot(configuration: nil)
                guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try png.write(to: snapshot)
            }
            var result: [String: Any] = [
                "renderer": metadata, "webView": metrics ?? [:],
                "resources": controller.resourceDiagnostics(),
                "elapsedMilliseconds": (CFAbsoluteTimeGetCurrent() - start) * 1000,
            ]
            if let interactions { result["htmlContainer"] = interactions }
            if let staticHTML { result["htmlStatic"] = staticHTML }
            if let noFind { result["noFind"] = noFind }
            if let nativeCopy { result["nativeCopy"] = nativeCopy }
            if let markdownImages { result["markdownImages"] = markdownImages }
            if let imageAccess { result["imageAccess"] = imageAccess }
            if let lineSelection { result["lineSelection"] = lineSelection }
            complete(result, status: lineSelection?["passed"] as? Bool == false ? 1 : 0)
        } catch { complete(["error": error.localizedDescription], status: 1) }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if !message.frameInfo.isMainFrame,
           message.frameInfo.request.url?.absoluteString.hasPrefix("quicklook-app://bundle/document/") == true { childFrame = message.frameInfo }
    }

    func complete(_ object: [String: Any], status: Int32) {
        guard !finished else { return }
        finished = true
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
            if let output { try data.write(to: output) }
            FileHandle.standardOutput.write(data)
            print("")
        } catch { fputs("\(error)\n", stderr) }
        exit(status)
    }
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else {
    print("Usage: quicklook-probe diagnose APP | inspect FILE... | render FILE [--checks html-container|html-static|no-find|native-copy|markdown-images|image-access|line-selection] [--output JSON] [--snapshot PNG] | network-positive LOOPBACK_ORIGIN [--output JSON] | network-parse LOOPBACK_ORIGIN --renderer-script JS [--output JSON]")
    exit(2)
}

if args[0] == "diagnose" {
    let appURL = URL(fileURLWithPath: args[1])
    Task.detached {
        let snapshot = await ExtensionDiagnostics.snapshot(hostURL: appURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            FileHandle.standardOutput.write(try encoder.encode(snapshot))
            print("")
            exit(0)
        } catch {
            fputs("\(error)\n", stderr)
            exit(1)
        }
    }
    dispatchMain()
} else if args[0] == "inspect" {
    var results: [[String: Any]] = []
    for path in args.dropFirst() {
        let url = URL(fileURLWithPath: path)
        var result: [String: Any] = ["file": url.path]
        do {
            let started = CFAbsoluteTimeGetCurrent()
            let payload = try PreviewPayload.load(url: url)
            result.merge([
                "mode": payload.mode, "language": payload.language, "encoding": payload.encoding,
                "totalBytes": payload.totalBytes, "bytesRead": payload.bytesRead,
                "truncated": payload.truncated, "characters": payload.text.count,
                "warning": payload.warning ?? "", "elapsedMilliseconds": (CFAbsoluteTimeGetCurrent() - started) * 1000,
            ]) { _, new in new }
            result["resolvedUTType"] = try url.resourceValues(forKeys: [.contentTypeKey]).contentType?.identifier
        } catch { result["error"] = error.localizedDescription }
        results.append(result)
    }
    let data = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
    FileHandle.standardOutput.write(data)
    print("")
} else if args[0] == "render" || args[0] == "network-positive" || args[0] == "network-parse" {
    func value(_ name: String) -> String? {
        guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
    func option(_ name: String) -> URL? {
        value(name).map { URL(fileURLWithPath: $0) }
    }
    guard value("--checks") == nil || ["html-container", "html-static", "no-find", "native-copy", "markdown-images", "image-access", "line-selection"].contains(value("--checks") ?? ""),
          value("--loopback-origin").map(validLoopbackOrigin) ?? true else { fputs("Invalid probe checks or loopback origin\n", stderr); exit(2) }
    MainActor.assumeIsolated {
        let app = ProbeApplication.shared
        app.setActivationPolicy(.prohibited)
        if args[0] == "network-positive" || args[0] == "network-parse" {
            guard validLoopbackOrigin(args[1]) else { fputs("Positive control requires an explicit loopback HTTP origin\n", stderr); exit(2) }
            var parseRenderer: Data?
            if args[0] == "network-parse" {
                guard let script = option("--renderer-script"), let data = try? Data(contentsOf: script) else { fputs("Parse control requires --renderer-script\n", stderr); exit(2) }
                parseRenderer = data
            }
            let control = LoopbackImageControl(origin: args[1], output: option("--output"), parseRenderer: parseRenderer)
            withExtendedLifetime(control) { app.run() }
        } else {
            let probe = RenderProbe(url: URL(fileURLWithPath: args[1]), output: option("--output"), snapshot: option("--snapshot"), checks: value("--checks"), loopbackOrigin: value("--loopback-origin"))
            withExtendedLifetime(probe) { app.run() }
        }
    }
} else {
    fputs("Unknown command: \(args[0])\n", stderr)
    exit(2)
}
