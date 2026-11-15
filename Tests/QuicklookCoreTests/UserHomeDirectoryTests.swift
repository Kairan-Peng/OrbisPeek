import Foundation
import XCTest
@testable import QuicklookCore

final class UserHomeDirectoryTests: XCTestCase {
    func testAccountHomeAllowsSpacesAndCustomOrNetworkLocations() throws {
        for path in ["/Users/Alice Smith", "/Volumes/Profiles/alice", "/Network/Servers/accounts/home/alice"] {
            let url = try XCTUnwrap(UserHomeDirectory.url(forAccountHomePath: path))
            XCTAssertTrue(url.isFileURL)
            XCTAssertTrue(url.hasDirectoryPath)
            XCTAssertEqual(url.path, path)
        }
    }

    func testMissingRelativeRootAndNulPathsCannotBecomePickerDefaults() {
        for path: String? in [nil, "", "alice", "~/alice", "file:///Users/alice", "/", "////", "/./", "/Users/..", "/Users/\0alice"] {
            XCTAssertNil(UserHomeDirectory.url(forAccountHomePath: path), String(describing: path))
        }
    }
}
