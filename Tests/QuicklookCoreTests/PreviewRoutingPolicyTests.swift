import XCTest
@testable import QuicklookCore

final class PreviewRoutingPolicyTests: XCTestCase {
    func testOnlyUnclassifiedDataUsesTextAttempt() {
        XCTAssertEqual(PreviewRoutingPolicy.decision(for: "public.data"), .system)
        XCTAssertEqual(PreviewRoutingPolicy.decision(for: "public.data", unclassifiedTextEnabled: false), .system)
        XCTAssertEqual(PreviewRoutingPolicy.decision(for: "public.data", unclassifiedTextEnabled: true), .unclassifiedText)
        for type in [nil, "public.item", "public.content", "public.text", "public.plain-text",
                     "public.png", "com.adobe.pdf", "public.html", "public.xhtml",
                     "public.mpeg-2-transport-stream", "com.apple.logic.exs", "com.adobe.edn",
                     "dyn.ah62d4rv4ge8086xcrf31n5xpr311s5v1qy6xe2u"] {
            XCTAssertEqual(PreviewRoutingPolicy.decision(for: type), .system, type ?? "missing type")
            XCTAssertEqual(PreviewRoutingPolicy.decision(for: type, unclassifiedTextEnabled: true), .system,
                           type ?? "missing type")
        }
    }

    func testKnownMarkdownAndJSONKeepTheirExistingRoute() {
        for type in ["public.markdown", "public.json", "public.swift-source"] {
            XCTAssertEqual(PreviewRoutingPolicy.decision(for: type), .supportedType)
            XCTAssertEqual(PreviewRoutingPolicy.decision(for: type, unclassifiedTextEnabled: true), .supportedType)
        }
    }

    func testPreviewDeclarationHasOneExplicitGenericRoute() {
        XCTAssertEqual(Set(FileTypeRegistry.previewUTIs), Set(FileTypeRegistry.supportedUTIs + ["public.data"]))
        XCTAssertFalse(FileTypeRegistry.previewUTIs.contains(where: { $0.hasPrefix("dyn.") }))
    }
}
