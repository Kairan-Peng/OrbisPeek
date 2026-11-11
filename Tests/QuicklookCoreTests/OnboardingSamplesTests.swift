import Foundation
import XCTest
@testable import QuicklookCore

final class OnboardingSamplesTests: XCTestCase {
    func testExplicitVerificationExportsFreshURLsWithAllDocumentsAndTheirImage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let stable = try OnboardingSamples.prepare(in: root)
        let first = try OnboardingSamples.prepare(in: root, freshForVerification: true)
        let second = try OnboardingSamples.prepare(in: root, freshForVerification: true)
        XCTAssertEqual(try OnboardingSamples.prepare(in: root), stable)
        for index in OnboardingSamples.previewFileNames.indices {
            XCTAssertNotEqual(first[index], stable[index])
            XCTAssertNotEqual(second[index], first[index])
            XCTAssertEqual(try Data(contentsOf: first[index]), try Data(contentsOf: stable[index]))
            XCTAssertEqual(try Data(contentsOf: second[index]), try Data(contentsOf: stable[index]))
        }
        for exported in [first, second] {
            XCTAssertEqual(exported.map(\.lastPathComponent), OnboardingSamples.previewFileNames)
            let directory = exported[0].deletingLastPathComponent()
            XCTAssertTrue(directory.lastPathComponent.hasPrefix("v1-check-"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("quicklook-sample.png").path))
        }
    }

    func testExportsOfflineDocumentsWithRelativeImageAndReusesUnchangedSamples() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try OnboardingSamples.prepare(in: root)
        XCTAssertEqual(first.map(\.lastPathComponent), OnboardingSamples.previewFileNames)
        XCTAssertEqual(try OnboardingSamples.prepare(in: root), first)
        let markdown = try String(contentsOf: first[0], encoding: .utf8)
        XCTAssertTrue(markdown.contains("(quicklook-sample.png)"))
        XCTAssertFalse(markdown.contains("https://"))
        let image = first[0].deletingLastPathComponent().appendingPathComponent("quicklook-sample.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: image.path))
    }

    func testPreservesEditedSamplesByExportingToANewDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try OnboardingSamples.prepare(in: root)
        try "用户保留的修改".write(to: first[0], atomically: true, encoding: .utf8)
        let second = try OnboardingSamples.prepare(in: root)
        XCTAssertNotEqual(first[0].deletingLastPathComponent(), second[0].deletingLastPathComponent())
        XCTAssertEqual(try String(contentsOf: first[0], encoding: .utf8), "用户保留的修改")
        XCTAssertTrue(try String(contentsOf: second[0], encoding: .utf8).contains("Quicklook 首次预览检查"))
    }

    func testDoesNotFollowAnExistingSampleDirectorySymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let other = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: other)
        }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("v1"), withDestinationURL: other)
        let urls = try OnboardingSamples.prepare(in: root)
        XCTAssertNotEqual(urls[0].deletingLastPathComponent(), root.appendingPathComponent("v1"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: other.path), [])
    }
}
