import AppKit
import Foundation
import QuicklookCore
import XCTest
@testable import QuicklookUI

@MainActor
final class ReaderWindowCoordinatorTests: XCTestCase {
    func testClosingReaderCancelsLoadInvalidatesPreviewAndReleasesAccess() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("synthetic.md")
        try Data("# synthetic".utf8).write(to: file)
        var access: ReaderDocumentAccess? = ReaderDocumentAccess(url: file)
        let weakAccess = WeakAccess(access)
        var closed = false
        let reader = ReaderWindowController(fileURL: file, access: access, onClose: { closed = true })
        access = nil
        reader.start()
        XCTAssertNotNil(weakAccess.value)
        reader.close()
        await Task.yield()
        XCTAssertTrue(closed)
        XCTAssertNil(weakAccess.value)
        XCTAssertNil(reader.preview.payload)
        XCTAssertNil(reader.loadTask)
    }
}

private final class WeakAccess {
    weak var value: ReaderDocumentAccess?
    init(_ value: ReaderDocumentAccess?) { self.value = value }
}
