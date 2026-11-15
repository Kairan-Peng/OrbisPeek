import Foundation
import XCTest
@testable import QuicklookUI

final class PreviewCommandStateTests: XCTestCase {
    private func report(_ request: UUID, _ generation: Int, _ sequence: Int, editor: Bool = false, composing: Bool = false, ready: Bool = true) -> [String: Any] {
        ["requestID": request.uuidString, "viewGeneration": generation, "stateSequence": sequence,
         "editorFocused": editor, "composing": composing, "hasBody": ready]
    }

    func testUnknownNewAndClosedStatesKeepNativeRouting() {
        var state = PreviewCommandState()
        XCTAssertFalse(state.routesBody)
        let request = UUID()
        state.reset(requestID: request)
        XCTAssertFalse(state.routesBody)
        state.receive(report(request, 1, 1), currentRequest: request)
        XCTAssertTrue(state.routesBody)
        state.reset()
        state.receive(report(request, 1, 2), currentRequest: request)
        XCTAssertFalse(state.routesBody)
    }

    func testOldRequestsGenerationsAndOutOfOrderFocusCannotReenableBodyCommands() {
        var state = PreviewCommandState()
        let request = UUID()
        state.reset(requestID: request)
        state.receive(report(request, 2, 3, editor: true), currentRequest: request)
        for old in [report(UUID(), 3, 4), report(request, 1, 4), report(request, 2, 2)] {
            state.receive(old, currentRequest: request)
            XCTAssertFalse(state.routesBody)
            XCTAssertTrue(state.editorFocused)
        }
        state.receive(report(request, 2, 4), currentRequest: request)
        XCTAssertTrue(state.routesBody)
        state.receive(report(request, 3, 5, ready: false), currentRequest: request)
        XCTAssertFalse(state.routesBody)
    }

    func testEditorAndCompositionKeepStandardNativeActions() {
        var state = PreviewCommandState()
        let request = UUID()
        state.reset(requestID: request)
        state.receive(report(request, 1, 1, composing: true), currentRequest: request)
        XCTAssertFalse(state.routesBody)
        state.receive(report(request, 1, 2, editor: true), currentRequest: request)
        XCTAssertFalse(state.routesBody)
    }
}
