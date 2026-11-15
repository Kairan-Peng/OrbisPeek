import Foundation

/// Only the trusted shell reports this routing hint. Commands recheck the live
/// DOM as well; unknown/new/closed state always keeps standard WebKit routing.
struct PreviewCommandState {
    private(set) var requestID: UUID?
    private(set) var generation = -1
    private(set) var sequence = -1
    private(set) var editorFocused = false
    private(set) var composing = false
    private(set) var hasBody = false

    mutating func reset(requestID: UUID? = nil) {
        self = PreviewCommandState()
        self.requestID = requestID
    }

    mutating func receive(_ body: [String: Any], currentRequest: UUID) {
        guard requestID == currentRequest, let request = body["requestID"] as? String,
              UUID(uuidString: request) == currentRequest,
              let next = body["viewGeneration"] as? Int, next >= 0, next >= generation,
              let nextSequence = body["stateSequence"] as? Int, nextSequence > sequence,
              let editor = body["editorFocused"] as? Bool,
              let composition = body["composing"] as? Bool, let ready = body["hasBody"] as? Bool else { return }
        generation = next
        sequence = nextSequence
        editorFocused = editor
        composing = composition
        hasBody = ready
    }

    var routesBody: Bool { requestID != nil && generation >= 0 && hasBody && !editorFocused && !composing }

    func allowsImageAccessRequest(_ body: [String: Any], currentRequest: UUID) -> Bool {
        guard body["action"] as? String == "openImageAccess", hasBody,
              requestID == currentRequest,
              let request = body["requestID"] as? String, UUID(uuidString: request) == currentRequest,
              let requestedGeneration = body["viewGeneration"] as? Int,
              requestedGeneration >= 0, requestedGeneration == generation else { return false }
        return true
    }
}
