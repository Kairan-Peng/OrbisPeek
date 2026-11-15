import Foundation
import XCTest
@testable import QuicklookUI

final class PreviewImageAccessRequestTests: XCTestCase {
    private func action(_ request: UUID, generation: Int) -> [String: Any] {
        ["action": "openImageAccess", "requestID": request.uuidString, "viewGeneration": generation]
    }

    private func ready(_ request: UUID, generation: Int, sequence: Int, hasBody: Bool = true) -> [String: Any] {
        ["requestID": request.uuidString, "viewGeneration": generation, "stateSequence": sequence,
         "hasBody": hasBody, "editorFocused": false, "composing": false]
    }

    func testImageAccessRequiresCurrentReadyBody() {
        let request = UUID()
        var state = PreviewCommandState()
        XCTAssertFalse(state.allowsImageAccessRequest(action(request, generation: 0), currentRequest: request))
        state.reset(requestID: request)
        XCTAssertFalse(state.allowsImageAccessRequest(action(request, generation: 0), currentRequest: request))
        state.receive(ready(request, generation: 1, sequence: 1), currentRequest: request)
        XCTAssertTrue(state.allowsImageAccessRequest(action(request, generation: 1), currentRequest: request))
    }

    func testOldModeAndFileActionsCannotOpenHost() {
        let first = UUID(), second = UUID()
        var state = PreviewCommandState()
        state.reset(requestID: first)
        state.receive(ready(first, generation: 2, sequence: 1), currentRequest: first)
        XCTAssertFalse(state.allowsImageAccessRequest(action(first, generation: 1), currentRequest: first))
        XCTAssertFalse(state.allowsImageAccessRequest(action(first, generation: 3), currentRequest: first))
        XCTAssertFalse(state.allowsImageAccessRequest(action(second, generation: 2), currentRequest: first))
        state.reset(requestID: second)
        XCTAssertFalse(state.allowsImageAccessRequest(action(first, generation: 2), currentRequest: second))
    }

    func testSourceLoadingAndClosedStatesRevokeOldActions() {
        let request = UUID()
        var state = PreviewCommandState()
        state.reset(requestID: request)
        state.receive(ready(request, generation: 1, sequence: 1), currentRequest: request)
        state.receive(ready(request, generation: 2, sequence: 2, hasBody: false), currentRequest: request)
        XCTAssertFalse(state.allowsImageAccessRequest(action(request, generation: 1), currentRequest: request))
        XCTAssertFalse(state.allowsImageAccessRequest(action(request, generation: 2), currentRequest: request))
        state.reset()
        state.receive(ready(request, generation: 2, sequence: 3), currentRequest: request)
        XCTAssertFalse(state.allowsImageAccessRequest(action(request, generation: 2), currentRequest: request))
    }

    func testMalformedOrUnrelatedActionsAreRejected() {
        let request = UUID()
        var state = PreviewCommandState()
        state.reset(requestID: request)
        state.receive(ready(request, generation: 1, sequence: 1), currentRequest: request)
        for body: [String: Any] in [
            [:], ["action": "copy", "requestID": request.uuidString, "viewGeneration": 1],
            ["action": "openImageAccess", "requestID": "invalid", "viewGeneration": 1],
            ["action": "openImageAccess", "requestID": request.uuidString, "viewGeneration": "1"],
            action(request, generation: -1),
        ] {
            XCTAssertFalse(state.allowsImageAccessRequest(body, currentRequest: request))
        }
    }
}
