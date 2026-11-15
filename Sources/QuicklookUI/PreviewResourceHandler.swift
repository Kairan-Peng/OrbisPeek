import Foundation
import ImageIO
import QuicklookCore
import UniformTypeIdentifiers
import WebKit

/// No file:// or network URL reaches the web view. Only bundled assets and bounded raster images.
final class PreviewResourceHandler: NSObject, WKURLSchemeHandler {
    private nonisolated let lock = NSLock()
    // These are accessed only while holding lock, including controller teardown.
    private nonisolated(unsafe) var document = HTMLPreviewDocument()
    private nonisolated(unsafe) var events: [[String: String]] = []
    private nonisolated(unsafe) var imageBytes = 0
    private nonisolated(unsafe) var imageCount = 0

    func beginRequest(_ request: UUID, documentURL: URL) {
        lock.lock()
        defer { lock.unlock() }
        document.beginRequest(request, documentURL: documentURL)
        events = []
        imageBytes = 0
        imageCount = 0
    }

    nonisolated func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        document.invalidate()
        events = []
        imageBytes = 0
        imageCount = 0
    }

    func resourceToken() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return document.resourceToken?.uuidString
    }

    func prepareHTML(_ html: String, requestID: UUID) throws -> URL {
        lock.lock()
        defer { lock.unlock() }
        return try document.prepare(html, requestID: requestID).url
    }

    func discardPreparedHTML(requestID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        document.discardPrepared(requestID: requestID)
    }

    func isCurrentDocument(_ url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return document.document(at: url) != nil
    }

    func diagnostics() -> [[String: String]] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        var imageToken: UUID?
        var diagnosticPath = url.path
        do {
            let data: Data
            let mime: String
            if let name = HTMLPreviewDocument.bundleResource(at: url) {
                guard let resource = Bundle.module.url(forResource: name, withExtension: nil) else {
                    throw CocoaError(.fileNoSuchFile)
                }
                data = try Data(contentsOf: resource)
                mime = ["html": "text/html", "js": "application/javascript", "css": "text/css"][resource.pathExtension] ?? "application/octet-stream"
            } else if url.scheme == "quicklook-app" {
                lock.lock()
                defer { lock.unlock() }
                guard let prepared = document.document(at: url) else { throw CocoaError(.fileReadNoPermission) }
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
                    "Content-Type": "text/html; charset=utf-8",
                    "Content-Security-Policy": HTMLPreviewDocument.contentSecurityPolicy,
                    "Cache-Control": "no-store",
                ])!
                task.didReceive(response)
                task.didReceive(prepared.data)
                task.didFinish()
                return
            } else if url.scheme == "quicklook-resource" {
                lock.lock()
                let imageResource = document.imageResource(at: url)
                let withinBudget = imageCount < 32 && imageBytes < 32 * 1024 * 1024
                if imageResource != nil && withinBudget { imageCount += 1 }
                lock.unlock()
                guard let imageResource else { throw CocoaError(.fileReadNoPermission) }
                imageToken = imageResource.token
                diagnosticPath = imageResource.relativePath
                guard withinBudget else { throw LocalResourceError.tooLarge }
                // URL.path decodes each percent-encoded path once. Policy also rejects traversal and symlink escapes.
                let relativePath = imageResource.relativePath
                let resource = try LocalResourcePolicy.resolve(relativePath: relativePath, documentURL: imageResource.documentURL)
                let handle = try FileHandle(forReadingFrom: resource)
                defer { try? handle.close() }
                let input = try handle.read(upToCount: LocalResourcePolicy.maximumImageBytes + 1) ?? Data()
                guard input.count <= LocalResourcePolicy.maximumImageBytes else { throw LocalResourceError.tooLarge }
                guard let source = CGImageSourceCreateWithData(input as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                      let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = info[kCGImagePropertyPixelWidth] as? Int,
                      let height = info[kCGImagePropertyPixelHeight] as? Int,
                      width > 0, height > 0, width <= 40_000_000 / height else {
                    throw LocalResourceError.unsupportedImage
                }
                // Rasterize only the first frame with a fixed pixel budget. WebKit never
                // receives an unbounded animation or a multi-page image container.
                guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2048,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary) else { throw LocalResourceError.unsupportedImage }
                let output = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
                    throw LocalResourceError.unsupportedImage
                }
                CGImageDestinationAddImage(destination, image, nil)
                guard CGImageDestinationFinalize(destination) else { throw LocalResourceError.unsupportedImage }
                data = output as Data
                mime = "image/png"
                lock.lock()
                defer { lock.unlock() }
                // ImageIO and file reads run without the lock. A replacement may have
                // revoked this capability while they ran; never account or send stale bytes.
                guard document.isCurrent(imageResource.token) else { throw CocoaError(.fileReadNoPermission) }
                guard data.count <= LocalResourcePolicy.maximumImageBytes,
                      imageBytes <= 32 * 1024 * 1024 - data.count else {
                    throw LocalResourceError.tooLarge
                }
                imageBytes += data.count
                record(["path": relativePath, "status": "loaded", "bytes": String(data.count)])
                respond(task, url: url, data: data, mime: mime)
                return
            } else {
                throw CocoaError(.fileReadNoPermission)
            }
            respond(task, url: url, data: data, mime: mime)
        } catch {
            lock.lock()
            if imageToken == nil || document.isCurrent(imageToken!) {
                record(["path": diagnosticPath, "status": "blocked", "reason": error.localizedDescription])
            }
            lock.unlock()
            task.didFailWithError(error)
        }
    }

    private func record(_ event: [String: String]) {
        if events.count < 256 { events.append(event) }
    }

    private func respond(_ task: WKURLSchemeTask, url: URL, data: Data, mime: String) {
        task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: mime.hasPrefix("text/") ? "utf-8" : nil))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        // Resources are loaded synchronously with strict bounds; no outstanding callbacks remain.
    }
}
