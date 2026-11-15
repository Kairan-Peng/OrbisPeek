import Foundation
import XCTest
@testable import QuicklookUI

final class HostImageAccessTargetTests: XCTestCase {
    func testReaderAndExtensionResolveTheirOwnContainingApp() {
        let app = URL(fileURLWithPath: "/Applications/OrbisPeek.app")
        XCTAssertEqual(HostImageAccessTarget.applicationURL(for: app), app)
        XCTAssertEqual(HostImageAccessTarget.applicationURL(for: app.appendingPathComponent("Contents/PlugIns/QuicklookPreview.appex")), app)
        let development = URL(fileURLWithPath: "/tmp/isolated/OrbisPeek.app", isDirectory: true)
        XCTAssertEqual(HostImageAccessTarget.applicationURL(for: development.appendingPathComponent("Contents/PlugIns/QuicklookPreview.appex")), development)
    }

    func testUnrelatedAndNonFileLocationsCannotBecomeLaunchTargets() {
        for url in [
            URL(string: "https://example.invalid/OrbisPeek.app")!,
            URL(fileURLWithPath: "/tmp/quicklook-probe"),
            URL(fileURLWithPath: "/tmp/QuicklookPreview.appex"),
            URL(fileURLWithPath: "/tmp/not-an-app/Contents/PlugIns/QuicklookPreview.appex"),
            URL(fileURLWithPath: "/Applications/OrbisPeek.app/Other/PlugIns/QuicklookPreview.appex"),
        ] {
            XCTAssertNil(HostImageAccessTarget.applicationURL(for: url))
        }
    }
}
