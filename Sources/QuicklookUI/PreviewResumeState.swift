import Foundation

/// A hidden preview revokes capabilities immediately. A later appearance may
/// reload only the same remembered file, unless any newer explicit action won.
struct PreviewResumeState {
    struct Ticket: Equatable { let epoch: UInt64; let url: URL; let policy: PreviewLoadPolicy }
    private var epoch: UInt64 = 0
    private var url: URL?
    private var policy = PreviewLoadPolicy.standard

    mutating func invalidate() { epoch &+= 1; url = nil; policy = .standard }
    mutating func suspend(_ url: URL?, policy: PreviewLoadPolicy = .standard) {
        invalidate()
        self.url = url
        self.policy = policy
    }
    var ticket: Ticket? { url.map { Ticket(epoch: epoch, url: $0, policy: policy) } }
    mutating func consume(_ ticket: Ticket) -> URL? {
        guard self.ticket == ticket else { return nil }
        invalidate()
        return ticket.url
    }
}
