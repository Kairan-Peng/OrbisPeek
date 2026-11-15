import Foundation
import XCTest
@testable import QuicklookUI

final class HTMLPreviewDocumentTests: XCTestCase {
    private let file = URL(fileURLWithPath: "/tmp/preview/document.md")

    func testOnlyExactCurrentDocumentRouteIsAccepted() throws {
        var state = HTMLPreviewDocument()
        let request = UUID()
        state.beginRequest(request, documentURL: file)
        let prepared = try state.prepare("<p>first</p>", requestID: request)
        XCTAssertEqual(state.document(at: prepared.url)?.data, Data("<p>first</p>".utf8))
        let token = prepared.url.pathComponents[2]
        for address in [
            "quicklook-app://other/document/\(token)/content.html",
            "quicklook-app://bundle:80/document/\(token)/content.html",
            "quicklook-app://user@bundle/document/\(token)/content.html",
            prepared.url.absoluteString + "?q=1", prepared.url.absoluteString + "#x",
            "quicklook-app://bundle/document/\(UUID().uuidString)/content.html",
            "quicklook-app://bundle/document/\(token)/wrong.html",
            "quicklook-app://bundle/document/\(token)/../content.html",
            "quicklook-app://bundle/document/\(token)/%2e%2e/content.html",
            "quicklook-app://bundle/document/\(token)/%63ontent.html",
            "quicklook-app://bundle/document/" + String(repeating: "x", count: 20_000),
        ] {
            XCTAssertNil(state.document(at: try XCTUnwrap(URL(string: address))), address)
        }
        let next = try state.prepare("<p>second</p>", requestID: request)
        XCTAssertNotEqual(next.url, prepared.url)
        XCTAssertNil(state.document(at: prepared.url))
        XCTAssertNotNil(state.document(at: next.url))
        state.invalidate()
        XCTAssertNil(state.document(at: next.url))
        XCTAssertNil(state.resourceToken)
        XCTAssertThrowsError(try state.prepare("<p>closed</p>", requestID: request))
    }

    func testUTF8BoundAndFailureDiscardPreviouslyPreparedData() throws {
        var state = HTMLPreviewDocument()
        let request = UUID()
        state.beginRequest(request, documentURL: file)
        let boundary = try state.prepare(String(repeating: "a", count: HTMLPreviewDocument.maximumHTMLBytes), requestID: request)
        XCTAssertEqual(boundary.data.count, HTMLPreviewDocument.maximumHTMLBytes)
        XCTAssertThrowsError(try state.prepare(String(repeating: "界", count: HTMLPreviewDocument.maximumHTMLBytes / 3 + 1), requestID: request))
        XCTAssertNil(state.document(at: boundary.url))
        let current = try state.prepare("current", requestID: request)
        XCTAssertThrowsError(try state.prepare("stale", requestID: UUID()))
        XCTAssertNotNil(state.document(at: current.url), "Old async callbacks cannot invalidate a newer request")
    }

    func testStaticRoutesAreExactAndIndependentOfDocumentState() throws {
        for name in ["index.html", "renderer.js", "styles.css"] {
            XCTAssertEqual(HTMLPreviewDocument.bundleResource(at: URL(string: "quicklook-app://bundle/\(name)")!), name)
            for address in ["quicklook-app://bundle/extra/\(name)", "quicklook-app://other/\(name)", "quicklook-app://bundle:80/\(name)", "quicklook-app://bundle/\(name)?x", "quicklook-app://bundle/\(name)#x", "quicklook-app://bundle/a/../\(name)"] {
                XCTAssertNil(HTMLPreviewDocument.bundleResource(at: URL(string: address)!), address)
            }
        }
    }

    func testImageResourceTokenCannotRebindOldURLsToANewDirectory() throws {
        var state = HTMLPreviewDocument()
        let first = UUID()
        let token = state.beginRequest(first, documentURL: file)
        let oldURL = URL(string: "quicklook-resource://local/\(token.uuidString)/assets/local%20image.png")!
        let resource = try XCTUnwrap(state.imageResource(at: oldURL))
        XCTAssertEqual(resource.documentURL, file)
        XCTAssertEqual(resource.relativePath, "assets/local image.png")
        XCTAssertEqual(resource.token, token)
        for address in ["quicklook-resource://local/assets/local.png", oldURL.absoluteString + "?x", oldURL.absoluteString + "#x", "quicklook-resource://local:80/\(token)/a.png", "quicklook-resource://other/\(token)/a.png", "quicklook-resource://local/\(token)/../a.png", "quicklook-resource://local/\(token)/%2e%2e/a.png", "quicklook-resource://local/\(token)/a\\b.png"] {
            XCTAssertNil(state.imageResource(at: URL(string: address)!), address)
        }
        state.beginRequest(UUID(), documentURL: URL(fileURLWithPath: "/tmp/other/new.md"))
        XCTAssertNil(state.imageResource(at: oldURL))
        XCTAssertFalse(state.isCurrent(resource.token))
        state.invalidate()
        XCTAssertNil(state.imageResource(at: oldURL))
    }

    func testFixedDocumentPolicyHasNoScriptOrNetworkPermission() {
        XCTAssertEqual(HTMLPreviewDocument.contentSecurityPolicy, "default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src quicklook-resource:; connect-src 'none'; font-src 'none'; media-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'")
    }
}
