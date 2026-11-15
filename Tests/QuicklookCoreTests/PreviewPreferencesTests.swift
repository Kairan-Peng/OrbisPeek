import Foundation
import XCTest
@testable import QuicklookCore

final class PreviewPreferencesTests: XCTestCase {
    private var root: URL!
    private var storeURL: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        storeURL = root.appendingPathComponent("preview-preferences-v1.json")
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testMissingSettingsDefaultOffWithoutCreatingAStore() {
        XCTAssertFalse(PreviewPreferences.readUnclassifiedTextEnabled(at: storeURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
    }

    func testExplicitChoicePersistsAndEveryReadUsesTheCurrentFile() throws {
        try PreviewPreferences.setUnclassifiedTextEnabled(true, storeURL: storeURL)
        XCTAssertTrue(PreviewPreferences.readUnclassifiedTextEnabled(at: storeURL))
        // Model another process replacing the shared store after this process
        // has already read it; a cached UserDefaults value would stay enabled.
        try Data(#"{"version":1,"unclassifiedTextEnabled":false}"#.utf8)
            .write(to: storeURL, options: .atomic)
        XCTAssertFalse(PreviewPreferences.readUnclassifiedTextEnabled(at: storeURL))
        try PreviewPreferences.setUnclassifiedTextEnabled(true, storeURL: storeURL)
        XCTAssertTrue(PreviewPreferences.readUnclassifiedTextEnabled(at: storeURL))
        try PreviewPreferences.setUnclassifiedTextEnabled(false, storeURL: storeURL)
        XCTAssertFalse(PreviewPreferences.readUnclassifiedTextEnabled(at: storeURL))
    }

    func testInvalidOrOversizedSettingsFailClosed() throws {
        for contents in [
            "", "not JSON", "{}", "true",
            #"{"version":2,"unclassifiedTextEnabled":true}"#,
            #"{"version":1,"unclassifiedTextEnabled":"true"}"#,
            #"{"version":1}"#,
            String(repeating: " ", count: 4097) + #"{"version":1,"unclassifiedTextEnabled":true}"#,
        ] {
            try Data(contents.utf8).write(to: storeURL, options: .atomic)
            XCTAssertFalse(PreviewPreferences.readUnclassifiedTextEnabled(at: storeURL), contents.prefix(80).description)
        }
        // A user can replace a damaged regular store with an explicit choice.
        try PreviewPreferences.setUnclassifiedTextEnabled(true, storeURL: storeURL)
        XCTAssertTrue(PreviewPreferences.readUnclassifiedTextEnabled(at: storeURL))
    }

    func testAtomicWriteReplacesTheStoreRatherThanChangingAnExistingReader() throws {
        try PreviewPreferences.setUnclassifiedTextEnabled(true, storeURL: storeURL)
        let handle = try FileHandle(forReadingFrom: storeURL)
        defer { try? handle.close() }
        try PreviewPreferences.setUnclassifiedTextEnabled(false, storeURL: storeURL)
        let oldData = try handle.readToEnd() ?? Data()
        let oldStore = try XCTUnwrap(JSONSerialization.jsonObject(with: oldData) as? [String: Any])
        XCTAssertEqual(oldStore["unclassifiedTextEnabled"] as? Bool, true)
        XCTAssertFalse(PreviewPreferences.readUnclassifiedTextEnabled(at: storeURL))
    }

    func testSymlinkAndDirectorySettingsAreRejectedWithoutChangingTheirTargets() throws {
        let target = root.appendingPathComponent("target.json")
        let original = Data(#"{"version":1,"unclassifiedTextEnabled":true}"#.utf8)
        try original.write(to: target)
        try FileManager.default.createSymbolicLink(at: storeURL, withDestinationURL: target)
        XCTAssertFalse(PreviewPreferences.readUnclassifiedTextEnabled(at: storeURL))
        XCTAssertThrowsError(try PreviewPreferences.setUnclassifiedTextEnabled(false, storeURL: storeURL))
        XCTAssertEqual(try Data(contentsOf: target), original)
        try FileManager.default.removeItem(at: storeURL)
        try FileManager.default.createDirectory(at: storeURL, withIntermediateDirectories: false)
        XCTAssertFalse(PreviewPreferences.readUnclassifiedTextEnabled(at: storeURL))
        XCTAssertThrowsError(try PreviewPreferences.setUnclassifiedTextEnabled(true, storeURL: storeURL))
    }

    func testUnconfiguredBuildCannotEnableTheFeature() throws {
        guard !PreviewPreferences.isAvailable else { return }
        XCTAssertFalse(PreviewPreferences.unclassifiedTextEnabled)
        XCTAssertThrowsError(try PreviewPreferences.setUnclassifiedTextEnabled(true))
    }
}
