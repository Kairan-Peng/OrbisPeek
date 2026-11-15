import Foundation
import XCTest
@testable import QuicklookCore

final class DirectoryAccessTests: XCTestCase {
    private let hostKey = "Quicklook.directoryAccess.hostBookmarks.v1"
    private let activatedKey = "Quicklook.directoryAccess.activatedBookmarks.v1"
    private var root: URL!
    private var storeURL: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        root = root.resolvingSymlinksInPath().standardizedFileURL
        storeURL = root.appendingPathComponent("grants.json")
        suite = "org.quicklook.preview.tests.directory-access.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        try FileManager.default.removeItem(at: root)
    }

    func testRemovingOneFolderPreservesOtherGrantAndBothOtherBookmarks() throws {
        let removed = UUID().uuidString, kept = UUID().uuidString
        let folder = root.appendingPathComponent("project")
        try seed([(removed, folder), (kept, root.appendingPathComponent("project-other"))])
        for key in [hostKey, activatedKey] {
            defaults.set([removed: Data([11]), kept: Data([22])], forKey: key)
        }

        try DirectoryAccess.revoke(folderURL: folder, storeURL: storeURL, defaults: defaults)

        let records = try grants()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?["id"] as? String, kept)
        XCTAssertEqual(records.first?["path"] as? String, root.appendingPathComponent("project-other").path)
        XCTAssertEqual(records.first?["implicitBookmark"] as? String, Data([2]).base64EncodedString())
        for key in [hostKey, activatedKey] {
            let cache = defaults.dictionary(forKey: key)
            XCTAssertNil(cache?[removed])
            XCTAssertEqual(cache?[kept] as? Data, Data([22]))
        }
    }

    func testRemovingParentDoesNotRemoveSeparatelyGrantedChild() throws {
        let parent = root.appendingPathComponent("project"), child = parent.appendingPathComponent("notes")
        let parentID = UUID().uuidString, childID = UUID().uuidString
        try seed([(parentID, parent), (childID, child)])

        try DirectoryAccess.revoke(folderURL: parent, storeURL: storeURL, defaults: defaults)

        XCTAssertEqual(try grants().map { $0["id"] as? String }, [childID])
    }

    func testRemovingUnknownFolderIsANoOpAndDoesNotCreateAMissingStore() throws {
        let id = UUID().uuidString, folder = root.appendingPathComponent("project")
        try seed([(id, folder)])
        let before = try Data(contentsOf: storeURL)
        defaults.set([id: Data([33])], forKey: hostKey)

        try DirectoryAccess.revoke(folderURL: root.appendingPathComponent("other"), storeURL: storeURL, defaults: defaults)

        XCTAssertEqual(try Data(contentsOf: storeURL), before)
        XCTAssertEqual(defaults.dictionary(forKey: hostKey)?[id] as? Data, Data([33]))
        let missing = root.appendingPathComponent("missing.json")
        try DirectoryAccess.revoke(folderURL: folder, storeURL: missing, defaults: defaults)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }

    func testCanonicalFolderRemovalAlsoWorksWhenTheFolderNoLongerExists() throws {
        let folder = root.appendingPathComponent("project")
        try seed([(UUID().uuidString, folder)])
        let normalized = root.appendingPathComponent("unused/../project")

        try DirectoryAccess.revoke(folderURL: normalized, storeURL: storeURL, defaults: defaults)

        XCTAssertEqual(try grants().count, 0)
    }

    func testChangedSymlinkCannotRevokeAnotherListedDirectory() throws {
        let original = root.appendingPathComponent("original"), destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let originalID = UUID().uuidString, destinationID = UUID().uuidString
        try seed([(originalID, original), (destinationID, destination)])
        try FileManager.default.removeItem(at: original)
        try FileManager.default.createSymbolicLink(at: original, withDestinationURL: destination)

        try DirectoryAccess.revoke(folderURL: original, storeURL: storeURL, defaults: defaults)

        XCTAssertEqual(try grants().map { $0["id"] as? String }, [destinationID])
    }

    func testInvalidStoreOrNonFileURLDoesNotAlterTheStoreOrCaches() throws {
        let id = UUID().uuidString
        let broken = Data("invalid JSON".utf8)
        try broken.write(to: storeURL)
        defaults.set([id: Data([44])], forKey: activatedKey)

        XCTAssertThrowsError(try DirectoryAccess.revoke(
            folderURL: root, storeURL: storeURL, defaults: defaults
        ))
        XCTAssertThrowsError(try DirectoryAccess.revoke(
            folderURL: URL(string: "https://example.invalid/project")!, storeURL: storeURL, defaults: defaults
        ))

        XCTAssertEqual(try Data(contentsOf: storeURL), broken)
        XCTAssertEqual(defaults.dictionary(forKey: activatedKey)?[id] as? Data, Data([44]))
    }

    private func seed(_ entries: [(String, URL)]) throws {
        let records: [[String: Any]] = entries.enumerated().map { index, entry in
            ["id": entry.0, "path": entry.1.standardizedFileURL.path,
             "implicitBookmark": Data([UInt8(index + 1)]).base64EncodedString()]
        }
        try JSONSerialization.data(withJSONObject: ["version": 1, "grants": records], options: [.sortedKeys]).write(to: storeURL)
    }

    private func grants() throws -> [[String: Any]] {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: storeURL)) as? [String: Any])
        return try XCTUnwrap(object["grants"] as? [[String: Any]])
    }
}
