import Foundation
import XCTest
@testable import QuicklookCore

final class FileTypeRegistryTests: XCTestCase {
    func testCoreFormatsHaveExplicitReadingModes() {
        XCTAssertEqual(FileTypeRegistry.classify(fileName: "README.MD")?.mode, "markdown")
        XCTAssertEqual(FileTypeRegistry.classify(fileName: "records.ndjson")?.mode, "jsonl")
        XCTAssertEqual(FileTypeRegistry.classify(fileName: "records.jsonl")?.mode, "jsonl")
        XCTAssertEqual(FileTypeRegistry.classify(fileName: "records.json")?.mode, "json")
        for name in ["settings.yaml", "settings.yml", "settings.toml", "settings.properties", "settings.ini", "app.log"] {
            XCTAssertNotNil(FileTypeRegistry.classify(fileName: name), name)
        }
    }

    func testSystemOwnedFormatsRemainOutsideRegistrationAndClassification() {
        let excludedSuffixes = ["txt", "text", "html", "htm", "xhtml", "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "csv", "svg", "png", "jpg", "mp4"]
        for suffix in excludedSuffixes {
            XCTAssertNil(FileTypeRegistry.classify(fileName: "sample.\(suffix)"), suffix)
            XCTAssertFalse(FileTypeRegistry.supportedExtensions.contains(suffix), suffix)
        }
        let excludedTypes = ["public.data", "public.content", "public.text", "public.plain-text", "public.source-code", "public.html", "public.xml-based-text", "com.adobe.pdf", "public.comma-separated-values-text", "public.svg-image", "public.mpeg-2-transport-stream", "public.avchd-mpeg-2-transport-stream", "com.apple.logic.exs", "com.adobe.edn", "com.apple.rez-source"]
        for type in excludedTypes {
            XCTAssertFalse(FileTypeRegistry.supportedUTIs.contains(type), type)
        }
    }

    func testFilenameRecognitionDoesNotRequireBroadTypeClaims() {
        let expected = ["Dockerfile": "dockerfile", "Dockerfile.dev": "dockerfile", "Containerfile": "dockerfile", "Makefile": "makefile", "CMakeLists.txt": "cmake", ".env": "dotenv", ".env.staging": "dotenv", ".gitignore": "plain-config", ".zshrc": "shell", "nginx.conf": "nginx"]
        for (filename, id) in expected {
            XCTAssertEqual(FileTypeRegistry.classify(fileName: filename)?.id, id, filename)
        }
        XCTAssertNil(FileTypeRegistry.classify(fileName: "file.unrelated-format"))
        XCTAssertNil(FileTypeRegistry.classify(fileName: ""))
    }

    func testManifestHasUniqueMeaningfulSuffixesAndValidModes() {
        XCTAssertGreaterThanOrEqual(FileTypeRegistry.supportedExtensions.count, 100)
        XCTAssertEqual(Set(FileTypeRegistry.all.map(\.id)).count, FileTypeRegistry.all.count)
        let suffixes = FileTypeRegistry.all.flatMap(\.extensions)
        XCTAssertEqual(suffixes.count, Set(suffixes).count)
        for type in FileTypeRegistry.all {
            XCTAssertTrue(["markdown", "json", "jsonl", "code"].contains(type.mode), type.id)
            XCTAssertFalse(type.language.isEmpty, type.id)
            for suffix in type.extensions {
                XCTAssertEqual(suffix, suffix.lowercased(), type.id)
                XCTAssertFalse(suffix.contains("."), type.id)
                XCTAssertFalse(suffix.isEmpty, type.id)
                XCTAssertEqual(FileTypeRegistry.classify(fileName: "sample.\(suffix)")?.id, type.id, suffix)
            }
        }
    }
}
