import AppKit
import Foundation
import QuicklookCore
import QuicklookUI
import UniformTypeIdentifiers
import WebKit

@MainActor
final class RenderProbe {
    let controller = PreviewWebController()
    let window: NSWindow
    let output: URL?
    let snapshot: URL?
    let start = CFAbsoluteTimeGetCurrent()
    var finished = false

    init(url: URL, output: URL?, snapshot: URL?) {
        self.output = output
        self.snapshot = snapshot
        window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 1000, height: 760), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = controller
        window.orderBack(nil)
        controller.onRender = { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let metadata): Task { await self.capture(metadata: metadata) }
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
        do {
            let metrics = try await controller.webView.callAsyncJavaScript("""
                await Promise.race([
                  Promise.all(Array.from(document.images).map(img => img.complete ? Promise.resolve() : new Promise(resolve => { img.onload = resolve; img.onerror = resolve; }))),
                  new Promise(resolve => setTimeout(resolve, 2000))
                ]);
                return {
                  title: document.title,
                  text: document.body.innerText.slice(0, 2000),
                  images: Array.from(document.images).map(img => ({src:img.getAttribute('src'),loaded:img.naturalWidth>0})),
                  scripts: document.scripts.length,
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
            complete([
                "renderer": metadata, "webView": metrics ?? [:],
                "resources": controller.resourceDiagnostics(),
                "elapsedMilliseconds": (CFAbsoluteTimeGetCurrent() - start) * 1000,
            ], status: 0)
        } catch { complete(["error": error.localizedDescription], status: 1) }
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
    print("Usage: quicklook-probe diagnose APP | inspect FILE... | render FILE [--output JSON] [--snapshot PNG]")
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
} else if args[0] == "render" {
    func option(_ name: String) -> URL? {
        guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[index + 1])
    }
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let probe = RenderProbe(url: URL(fileURLWithPath: args[1]), output: option("--output"), snapshot: option("--snapshot"))
        withExtendedLifetime(probe) { app.run() }
    }
} else {
    fputs("Unknown command: \(args[0])\n", stderr)
    exit(2)
}
