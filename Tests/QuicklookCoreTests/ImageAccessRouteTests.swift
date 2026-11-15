import Foundation
import XCTest
@testable import QuicklookCore

final class ImageAccessRouteTests: XCTestCase {
    func testFixedRouteAllowsOnlyCaseEquivalentSchemeAndHost() throws {
        XCTAssertEqual(ImageAccessRoute.url.absoluteString, "orbispeek://image-access")
        for value in ["orbispeek://image-access", "ORBISPEEK://IMAGE-ACCESS"] {
            XCTAssertTrue(ImageAccessRoute.matches(try XCTUnwrap(URL(string: value))), value)
        }
    }

    func testRouteRejectsPathsPayloadsCredentialsPortsAndOtherSchemes() throws {
        for value in [
            "orbispeek://image-access/", "orbispeek://image-access/path", "orbispeek://image-access?", "orbispeek://image-access?folder=/tmp",
            "orbispeek://image-access#", "orbispeek://image-access#folder", "orbispeek://user@image-access", "orbispeek://user:password@image-access",
            "orbispeek://image-access:42", "orbispeek://image-access.example", "orbispeek://image-access./", "orbispeek://%69mage-access",
            "orbispeek:image-access", "https://image-access", "file:///image-access", "orbispeek://other",
        ] {
            XCTAssertFalse(ImageAccessRoute.matches(try XCTUnwrap(URL(string: value))), value)
        }
    }
}
