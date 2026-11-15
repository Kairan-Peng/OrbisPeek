import Foundation
import XCTest
@testable import QuicklookUI

@MainActor
final class ReaderFileOpenRouterTests: XCTestCase {
    func testColdDocumentEventsWaitForOneModelAndDrainOnceInOrder() {
        let router = ReaderFileOpenRouter()
        let first = URL(fileURLWithPath: "/synthetic/first.html")
        let second = URL(fileURLWithPath: "/synthetic/second.xhtml")
        var opened: [URL] = []
        router.open([first, second])
        XCTAssertTrue(opened.isEmpty)
        router.connect { opened.append($0) }
        XCTAssertEqual(opened, [first, second])
        router.connect { _ in XCTFail("Recreating setup must not duplicate the model route") }
        XCTAssertEqual(opened, [first, second])
    }

    func testModelRouteSurvivesSetupClosureAndPreservesSeparateOpenActions() {
        let router = ReaderFileOpenRouter()
        let file = URL(fileURLWithPath: "/synthetic/document.html")
        var opened: [URL] = []
        router.connect { opened.append($0) }
        router.open([file])
        router.open([file])
        XCTAssertEqual(opened, [file, file])
    }
}
