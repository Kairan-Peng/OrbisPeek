import AppKit
import WebKit
import XCTest
@testable import QuicklookUI

@MainActor
final class PreviewCopyDispatchTests: XCTestCase {
    private func state(editor: Bool = false, composing: Bool = false, ready: Bool = true) -> PreviewCommandState {
        let request = UUID()
        var state = PreviewCommandState()
        state.reset(requestID: request)
        state.receive(["requestID": request.uuidString, "viewGeneration": 1, "stateSequence": 1,
                       "editorFocused": editor, "composing": composing, "hasBody": ready], currentRequest: request)
        return state
    }

    func testServiceForwardedCopyStopsAtPreviewBodyExactlyOnce() {
        _ = NSApplication.shared
        let view = PreviewWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let bodyState = state()
        view.commandState = { bodyState }
        var commands: [String] = []
        view.runCommand = { commands.append($0) }
        let service = ForwardingCopyService(view: view)
        view.nextResponder = service

        // Quick Look forwards its Copy action through doCommandBySelector:.
        // Bound the synthetic service so the regression fails without exhausting
        // the test process's stack like the actual Finder service did.
        XCTAssertTrue(NSApp.sendAction(#selector(NSText.copy(_:)), to: service, from: nil))
        XCTAssertEqual(service.copyCount, 1, "Copy must not return to the service responder")
        XCTAssertEqual(commands, ["copy"])
    }

    func testDirectCommandCopyUsesBodyCommandOnce() {
        _ = NSApplication.shared
        let view = PreviewWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let bodyState = state()
        view.commandState = { bodyState }
        var commands: [String] = []
        view.runCommand = { commands.append($0) }
        view.doCommand(by: #selector(NSText.copy(_:)))
        XCTAssertEqual(commands, ["copy"])
    }

    func testEditorCompositionAndUnavailableBodyCannotReenterService() {
        _ = NSApplication.shared
        for routingState in [state(editor: true), state(composing: true), state(ready: false), PreviewCommandState()] {
            let view = PreviewWebView(frame: .zero, configuration: WKWebViewConfiguration())
            view.commandState = { routingState }
            var commands: [String] = []
            view.runCommand = { commands.append($0) }
            let service = ForwardingCopyService(view: view)
            view.nextResponder = service
            XCTAssertTrue(NSApp.sendAction(#selector(NSText.copy(_:)), to: service, from: nil))
            XCTAssertEqual(service.copyCount, 1)
            XCTAssertTrue(commands.isEmpty)
        }
    }

    func testUnavailableBodySupplementalCopyCannotDispatchAStaleCommand() {
        _ = NSApplication.shared
        for routingState in [state(ready: false), PreviewCommandState()] {
            let view = PreviewWebView(frame: .zero, configuration: WKWebViewConfiguration())
            view.commandState = { routingState }
            var commands: [String] = []
            view.runCommand = { commands.append($0) }
            let selector = #selector(NSText.copy(_:))
            XCTAssertFalse(view.responds(to: selector))
            let target = view.supplementalTarget(forAction: selector, sender: nil)
            XCTAssertNotNil(target)
            XCTAssertTrue(NSApp.sendAction(selector, to: target, from: nil))
            XCTAssertTrue(commands.isEmpty)
        }
    }

    func testSupplementalTargetRechecksStateAtActionTime() {
        _ = NSApplication.shared
        let view = PreviewWebView(frame: .zero, configuration: WKWebViewConfiguration())
        var routingState = state()
        view.commandState = { routingState }
        var commands: [String] = []
        view.runCommand = { commands.append($0) }
        let selector = #selector(NSText.copy(_:))
        let target = view.supplementalTarget(forAction: selector, sender: nil)
        routingState.reset()
        XCTAssertTrue(NSApp.sendAction(selector, to: target, from: nil))
        XCTAssertTrue(commands.isEmpty)
    }
}

@MainActor
private final class ForwardingCopyService: NSResponder {
    private weak var view: PreviewWebView?
    private(set) var copyCount = 0
    init(view: PreviewWebView) { self.view = view; super.init() }
    required init?(coder: NSCoder) { nil }

    @objc func copy(_ sender: Any?) {
        copyCount += 1
        guard copyCount < 8 else { return }
        view?.doCommand(by: #selector(NSText.copy(_:)))
    }
}
