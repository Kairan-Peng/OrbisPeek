import Foundation
import XCTest
@testable import QuicklookUI

final class PreviewResumeStateTests: XCTestCase {
    private let first = URL(fileURLWithPath: "/tmp/first.html")
    private let second = URL(fileURLWithPath: "/tmp/second.html")

    func testHiddenFileCanResumeExactlyOnce() throws {
        var state = PreviewResumeState()
        state.suspend(first)
        let ticket = try XCTUnwrap(state.ticket)
        XCTAssertEqual(state.consume(ticket), first)
        XCTAssertNil(state.consume(ticket))
        XCTAssertNil(state.ticket)
    }

    func testExplicitCloseOrNewFileInvalidatesScheduledResume() throws {
        for replacement in [nil, second] {
            var state = PreviewResumeState()
            state.suspend(first)
            let old = try XCTUnwrap(state.ticket)
            state.invalidate()
            XCTAssertNil(state.consume(old))
            state.suspend(replacement)
            XCTAssertNil(state.consume(old))
            XCTAssertEqual(state.ticket?.url, replacement)
        }
    }

    func testResumeRetainsStrictUnclassifiedPolicy() throws {
        var state = PreviewResumeState()
        state.suspend(first, policy: .unclassifiedText)
        let ticket = try XCTUnwrap(state.ticket)
        XCTAssertEqual(ticket.policy, .unclassifiedText)
        XCTAssertEqual(ticket.policy.decodingPolicy, .verifiedUnicode)
        XCTAssertTrue(ticket.policy.forcePlainText)
        XCTAssertFalse(ticket.policy.showsLoadFailure)
        XCTAssertEqual(state.consume(ticket), first)

        state.suspend(first)
        XCTAssertEqual(state.ticket?.policy, .standard)
        XCTAssertNil(state.consume(ticket))
    }
}
