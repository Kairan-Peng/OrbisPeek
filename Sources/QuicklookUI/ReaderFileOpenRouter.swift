import Foundation

/// AppKit can deliver documents before the setup view attaches. Preserve their
/// original URLs until the one app model connects, including their access scope.
@MainActor
public final class ReaderFileOpenRouter {
    private var pending: [URL] = []
    private var handler: ((URL) -> Void)?

    public init() {}

    public func connect(_ handler: @escaping (URL) -> Void) {
        guard self.handler == nil else { return }
        self.handler = handler
        let documents = pending
        pending.removeAll()
        for document in documents { handler(document) }
    }

    public func open(_ documents: [URL]) {
        guard let handler else { pending.append(contentsOf: documents); return }
        for document in documents { handler(document) }
    }
}
