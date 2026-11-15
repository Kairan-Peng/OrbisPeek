import Foundation
import XCTest
@testable import QuicklookCore

final class PreviewPayloadFallbackTests: XCTestCase {
    private func withFile<T>(name: String, data: Data, _ body: (URL) throws -> T) throws -> T {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent(name)
        try data.write(to: file)
        return try body(file)
    }

    func testForcedPlainTextDoesNotInterpretARecognizedDocumentName() throws {
        let documents = [
            ("note.md", "# 标题\n**原文**", "markdown", "markdown"),
            ("page.html", "<h1>原文</h1>", "html", "html"),
            ("data.json", "{\"value\":123}", "json", "json"),
        ]
        for (name, text, mode, language) in documents {
            try withFile(name: name, data: Data(text.utf8)) { file in
                let normal = try PreviewPayload.load(url: file)
                XCTAssertEqual(normal.mode, mode)
                XCTAssertEqual(normal.language, language)
                let fallback = try PreviewPayload.load(url: file, decodingPolicy: .verifiedUnicode,
                                                       forcePlainText: true)
                XCTAssertEqual(fallback.mode, "code")
                XCTAssertEqual(fallback.language, "plaintext")
                XCTAssertEqual(fallback.text, text)
                XCTAssertEqual(fallback.fileName, name)
                XCTAssertEqual(fallback.totalBytes, Int64(text.utf8.count))
                XCTAssertNil(fallback.warning)
            }
        }
    }

    func testFallbackCarriesStrictDecodingPolicyAndReadLimit() throws {
        try withFile(name: "without-suffix", data: Data("a🧭中文后续内容".utf8)) { file in
            let payload = try PreviewPayload.load(url: file, limit: 4, decodingPolicy: .verifiedUnicode,
                                                  forcePlainText: true)
            XCTAssertEqual(payload.text, "a")
            XCTAssertTrue(payload.truncated)
            XCTAssertEqual(payload.bytesRead, 8)
            XCTAssertEqual(payload.mode, "code")
            XCTAssertEqual(payload.language, "plaintext")
        }
        let opaque = Data([0xA1, 0xB1, 0xC1, 0xD1, 0xE1, 0xF1])
        try withFile(name: "opaque", data: opaque) { file in
            XCTAssertThrowsError(try PreviewPayload.load(url: file, decodingPolicy: .verifiedUnicode,
                                                         forcePlainText: true))
        }
    }
}
