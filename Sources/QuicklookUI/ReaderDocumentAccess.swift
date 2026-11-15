import Foundation

/// Standard AppKit document-open URLs supply the access authority. Start it
/// before the asynchronous load and retain it until this reader closes.
final class ReaderDocumentAccess {
    let url: URL
    private let started: Bool

    init(url: URL) {
        self.url = url
        started = url.startAccessingSecurityScopedResource()
    }
    deinit { if started { url.stopAccessingSecurityScopedResource() } }
}
