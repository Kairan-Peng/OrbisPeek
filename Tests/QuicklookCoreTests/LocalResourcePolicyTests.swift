import Foundation
import XCTest
@testable import QuicklookCore

final class LocalResourcePolicyTests: XCTestCase {
    func testAllowsSiblingAndRejectsTraversalSymlinkAndActiveFormats() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = base.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let image = folder.appendingPathComponent("picture.png")
        try Data([137, 80, 78, 71]).write(to: image)
        let document = folder.appendingPathComponent("README.md")
        XCTAssertEqual(try LocalResourcePolicy.resolve(relativePath: "picture.png", documentURL: document), image)
        for path in ["../picture.png", "/picture.png", "a\\b.png", "picture.svg", "picture.html"] {
            XCTAssertThrowsError(try LocalResourcePolicy.resolve(relativePath: path, documentURL: document), path)
        }
        let outside = base.appendingPathComponent("outside.png")
        try Data().write(to: outside)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link.png"), withDestinationURL: outside)
        XCTAssertThrowsError(try LocalResourcePolicy.resolve(relativePath: "link.png", documentURL: document))
    }
}
