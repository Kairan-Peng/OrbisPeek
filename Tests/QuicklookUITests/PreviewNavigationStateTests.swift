import Foundation
import XCTest
@testable import QuicklookUI

final class PreviewNavigationStateTests: XCTestCase {
    func testShellNavigationRequiresCurrentSuccessfulRenderAndTrustedSource() {
        var state = PreviewNavigationState()
        let request = UUID()
        XCTAssertFalse(state.allowsUserNavigation(requestID: request, trustedSource: true))
        state.begin(requestID: request)
        XCTAssertFalse(state.allowsUserNavigation(requestID: request, trustedSource: true))
        state.didRender(requestID: request)
        XCTAssertTrue(state.allowsUserNavigation(requestID: request, trustedSource: true))
        XCTAssertFalse(state.allowsUserNavigation(requestID: request, trustedSource: false))
        state.invalidate()
        XCTAssertFalse(state.allowsUserNavigation(requestID: request, trustedSource: true), "The same fixed shell URL is still loaded after invalidation")
        state.didRender(requestID: request)
        XCTAssertFalse(state.allowsUserNavigation(requestID: request, trustedSource: true), "Late failed/closed render cannot restore permission")
    }

    func testBeginningNewLoadRevokesOldShellUntilNewRenderAndRejectsLateOldCompletion() {
        var state = PreviewNavigationState()
        let first = UUID(), second = UUID()
        state.begin(requestID: first)
        state.didRender(requestID: first)
        state.begin(requestID: second)
        XCTAssertFalse(state.allowsUserNavigation(requestID: first, trustedSource: true))
        XCTAssertFalse(state.allowsUserNavigation(requestID: second, trustedSource: true), "Old shell can remain at the fixed URL while new payload is loading")
        state.didRender(requestID: first)
        XCTAssertFalse(state.allowsUserNavigation(requestID: second, trustedSource: true))
        state.didRender(requestID: second)
        XCTAssertTrue(state.allowsUserNavigation(requestID: second, trustedSource: true))
        XCTAssertFalse(state.allowsUserNavigation(requestID: first, trustedSource: true))
    }
}
