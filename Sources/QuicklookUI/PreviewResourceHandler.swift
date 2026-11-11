import Foundation
import ImageIO
import QuicklookCore
import UniformTypeIdentifiers
import WebKit

/// No file:// or network URL reaches the web view. Only bundled assets and bounded raster images.
final class PreviewResourceHandler: NSObject, WKURLSchemeHandler {
    private let lock = NSLock()
    private var documentURL: URL?
    private var events: [[String: String]] = []
    private var imageBytes = 0
    private var imageCount = 0

    func setDocument(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        documentURL = url
        events = []
        imageBytes = 0
        imageCount = 0
    }

    func diagnostics() -> [[String: String]] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        do {
            let data: Data
            let mime: String
            if url.scheme == "quicklook-app", url.host == "bundle" {
                let name = url.lastPathComponent
                guard ["index.html", "renderer.js", "styles.css"].contains(name),
                      let resource = Bundle.module.url(forResource: name, withExtension: nil) else {
                    throw CocoaError(.fileNoSuchFile)
                }
                data = try Data(contentsOf: resource)
                mime = ["html": "text/html", "js": "application/javascript", "css": "text/css"][resource.pathExtension] ?? "application/octet-stream"
            } else if url.scheme == "quicklook-resource", url.host == "local" {
                lock.lock()
                let document = documentURL
                let withinBudget = imageCount < 32 && imageBytes < 32 * 1024 * 1024
                imageCount += 1
                lock.unlock()
                guard let document, withinBudget else { throw LocalResourceError.tooLarge }
                // URL.path decodes each percent-encoded path once. Policy also rejects traversal and symlink escapes.
                let relativePath = String(url.path.dropFirst())
                let resource = try LocalResourcePolicy.resolve(relativePath: relativePath, documentURL: document)
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
                guard data.count <= LocalResourcePolicy.maximumImageBytes,
                      imageBytes <= 32 * 1024 * 1024 - data.count else {
                    lock.unlock()
                    throw LocalResourceError.tooLarge
                }
                imageBytes += data.count
                events.append(["path": relativePath, "status": "loaded", "bytes": String(data.count)])
                lock.unlock()
            } else {
                throw CocoaError(.fileReadNoPermission)
            }
            task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: mime.hasPrefix("text/") ? "utf-8" : nil))
            task.didReceive(data)
            task.didFinish()
        } catch {
            lock.lock()
            events.append(["path": url.path, "status": "blocked", "reason": error.localizedDescription])
            lock.unlock()
            task.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        // Resources are loaded synchronously with strict bounds; no outstanding callbacks remain.
    }
}
