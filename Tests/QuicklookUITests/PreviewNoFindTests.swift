import AppKit
import WebKit
import XCTest
@testable import QuicklookUI

@MainActor
final class PreviewNoFindTests: XCTestCase {
    func testNativeFindIsUnavailableAndCommandFIsConsumedWithoutDispatch() {
        _ = NSApplication.shared
        let view = PreviewWebView(frame: .zero, configuration: WKWebViewConfiguration())
        var commands: [String] = []
        view.runCommand = { commands.append($0) }
        XCTAssertFalse(view.responds(to: #selector(NSResponder.performTextFinderAction(_:))))
        view.performTextFinderAction(nil)
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                    timestamp: 0, windowNumber: 0, context: nil, characters: "f",
                                    charactersIgnoringModifiers: "f", isARepeat: false, keyCode: 3)!
        XCTAssertTrue(view.performKeyEquivalent(with: event))
        XCTAssertTrue(commands.isEmpty)
    }
}
