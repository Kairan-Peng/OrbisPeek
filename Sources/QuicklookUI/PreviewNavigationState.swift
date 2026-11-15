import Foundation

/// A fixed shell URL identifies trusted code, but does not prove that the
/// current request has finished rendering. Revoke user navigation while a new
/// load is pending and after failure/dismissal, even if that shell remains.
struct PreviewNavigationState {
    private var activeRequest: UUID?
    private var renderedRequest: UUID?

    mutating func begin(requestID: UUID) {
        activeRequest = requestID
        renderedRequest = nil
    }

    mutating func didRender(requestID: UUID) {
        guard activeRequest == requestID else { return }
        renderedRequest = requestID
    }

    mutating func invalidate() {
        activeRequest = nil
        renderedRequest = nil
    }

    func allowsUserNavigation(requestID: UUID, trustedSource: Bool) -> Bool {
        trustedSource && activeRequest == requestID && renderedRequest == requestID
    }
}
