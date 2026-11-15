import CoreFoundation
import Foundation
import XCTest
@testable import QuicklookCore

final class TextLoaderTests: XCTestCase {
    private func load(_ data: Data, limit: Int = TextLoader.defaultLimit,
                      policy: TextDecodingPolicy = .automatic) throws -> LoadedText {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.log")
        try data.write(to: url)
        return try TextLoader.load(url: url, limit: limit, decodingPolicy: policy)
    }

    func testEmptyFileHasReadableEmptyPreview() throws {
        let result = try load(Data())
        XCTAssertEqual(result.text, "")
        XCTAssertEqual(result.encoding, "UTF-8")
        XCTAssertEqual(result.totalBytes, 0)
        XCTAssertEqual(result.bytesRead, 0)
        XCTAssertFalse(result.truncated)
    }

    func testUTF8ChineseAndEmojiRemainUnchanged() throws {
        let text = "# 配置\n名称 = 轻量预览\nemoji = 🧭\n"
        let result = try load(Data(text.utf8))
        XCTAssertEqual(result.text, text)
        XCTAssertEqual(result.encoding, "UTF-8")
        XCTAssertNil(result.warning)
        XCTAssertFalse(result.truncated)
    }

    func testUTF8BOMIsRemoved() throws {
        let result = try load(Data([0xEF, 0xBB, 0xBF]) + Data("中文".utf8))
        XCTAssertEqual(result.text, "中文")
        XCTAssertEqual(result.encoding, "UTF-8 BOM")
    }

    func testUTF16BOMIsDetectedBeforeBinaryNULCheck() throws {
        let text = "# 中文配置\nname=Quicklook\nemoji=🧭\n"
        for (encoding, bom, name) in [
            (String.Encoding.utf16LittleEndian, [UInt8(0xFF), 0xFE], "UTF-16 LE"),
            (.utf16BigEndian, [UInt8(0xFE), 0xFF], "UTF-16 BE")
        ] {
            let result = try load(Data(bom) + XCTUnwrap(text.data(using: encoding)))
            XCTAssertEqual(result.text, text)
            XCTAssertEqual(result.encoding, name)
            XCTAssertNil(result.warning)
        }
    }

    func testUTF32BOMIsNotMistakenForUTF16() throws {
        let text = "中文 🧭 UTF32"
        let result = try load(Data([0xFF, 0xFE, 0, 0]) + XCTUnwrap(text.data(using: .utf32LittleEndian)))
        XCTAssertEqual(result.text, text)
        XCTAssertEqual(result.encoding, "UTF-32 LE")
    }

    func testBOMlessUTF16ASCIIAndChineseConfiguration() throws {
        let text = "server.name = 中文服务器\nenabled = true\nport = 8080\n"
        for encoding in [String.Encoding.utf16LittleEndian, .utf16BigEndian] {
            let result = try load(XCTUnwrap(text.data(using: encoding)))
            XCTAssertEqual(result.text, text)
            XCTAssertNotNil(result.warning)
        }
    }

    func testUTF8TruncationDoesNotSubstituteIncompleteCodePoint() throws {
        let data = Data("a🧭中文后续内容".utf8)
        for limit in 1...10 {
            let result = try load(data, limit: limit)
            XCTAssertTrue(result.truncated)
            XCTAssertTrue("a🧭中文后续内容".hasPrefix(result.text))
            XCTAssertFalse(result.text.contains("�"))
            XCTAssertEqual(result.encoding, "UTF-8")
            XCTAssertLessThanOrEqual(result.bytesRead, limit + 4)
        }
    }

    func testUTF16TruncationDoesNotLeaveHighSurrogate() throws {
        let text = "a🧭中文后续内容"
        let data = Data([0xFF, 0xFE]) + (try XCTUnwrap(text.data(using: .utf16LittleEndian)))
        for limit in 4...12 {
            let result = try load(data, limit: limit)
            XCTAssertTrue(text.hasPrefix(result.text))
            XCTAssertFalse(result.text.contains("�"))
            XCTAssertEqual(result.encoding, "UTF-16 LE")
        }
    }

    func testLegacyGB18030UsesSystemDetectorWithoutLossyConversion() throws {
        let text = String(repeating: "应用名称=轻量文档预览\n说明=这是用于检查中文配置文件编码的测试内容，支持日志和源代码。\n扩展字符=𠀀🧭\n", count: 6)
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let result = try load(XCTUnwrap(text.data(using: encoding)))
        XCTAssertEqual(result.text, text)
        XCTAssertNotNil(result.warning)
    }

    func testLegacyTruncationKeepsACompleteCharacterPrefix() throws {
        let text = String(repeating: "应用名称=轻量文档预览\n说明=这是用于检查中文配置文件编码的测试内容，支持日志和源代码。\n", count: 100)
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let data = try XCTUnwrap(text.data(using: encoding))
        for limit in 127...130 {
            let result = try load(data, limit: limit)
            XCTAssertTrue(result.truncated)
            XCTAssertTrue(text.hasPrefix(result.text))
            XCTAssertNotNil(result.warning)
            XCTAssertLessThanOrEqual(result.bytesRead, limit + 4)
        }
    }

    func testLegacyBig5UsesSystemDetectorWithoutLossyConversion() throws {
        let text = String(repeating: "應用名稱=文件預覽\n說明=這是用來檢查繁體中文設定檔編碼的測試內容，支援日誌和程式碼。\n", count: 6)
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))
        let result = try load(XCTUnwrap(text.data(using: encoding)))
        XCTAssertEqual(result.text, text)
        XCTAssertNotNil(result.warning)
    }

    func testLegacyShiftJISUsesSystemDetectorWithoutLossyConversion() throws {
        let text = String(repeating: "アプリケーション名=書類プレビュー\n説明=これは日本語の設定ファイルとログの文字コードを確認するためのテストです。\n", count: 6)
        let result = try load(XCTUnwrap(text.data(using: .shiftJIS)))
        XCTAssertEqual(result.text, text)
        XCTAssertNotNil(result.warning)
    }

    func testRejectsBinaryEvenWhenBytesCouldBeUTF16() throws {
        let binary = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0])
        XCTAssertThrowsError(try load(binary))
        XCTAssertThrowsError(try load(Data([0x01, 0x02, 0x03, 0x00, 0x15, 0x07])))
    }

    func testRejectsTruncatedBOMInsteadOfGuessingAnotherEncoding() throws {
        XCTAssertThrowsError(try load(Data([0xFF, 0xFE, 0x41])))
    }

    func testLargeSparseFileReadsOnlyBoundedPrefix() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("large.jsonl")
        let record = Data("{\"message\":\"中文\",\"ok\":true}\n".utf8)
        try Data(repeating: 0x20, count: 1024).write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: record)
        try handle.truncate(atOffset: 1_073_741_824)
        try handle.close()
        let result = try TextLoader.load(url: url, limit: 128)
        XCTAssertEqual(result.totalBytes, 1_073_741_824)
        XCTAssertEqual(result.bytesRead, 132)
        XCTAssertTrue(result.truncated)
        XCTAssertTrue(result.text.hasPrefix("{\"message\":\"中文\""))
    }

    func testRejectsDirectoryAndInvalidByteLimit() throws {
        XCTAssertThrowsError(try TextLoader.load(url: FileManager.default.temporaryDirectory))
        XCTAssertThrowsError(try load(Data("text".utf8), limit: 0))
    }

    func testVerifiedUnicodeAcceptsEmptyAndStrictUTF8WithoutInference() throws {
        for text in ["", "普通文本\n\t缩进 🧭\n"] {
            let result = try load(Data(text.utf8), policy: .verifiedUnicode)
            XCTAssertEqual(result.text, text)
            XCTAssertEqual(result.encoding, "UTF-8")
            XCTAssertNil(result.warning)
            XCTAssertFalse(result.truncated)
        }
    }

    func testVerifiedUnicodeAcceptsExplicitBOMsAndTruncatedCharacterBoundaries() throws {
        let text = "a🧭中文后续内容，用于验证有界前缀。"
        let encodings: [(String.Encoding, [UInt8], String)] = [
            (.utf8, [0xEF, 0xBB, 0xBF], "UTF-8 BOM"),
            (.utf16LittleEndian, [0xFF, 0xFE], "UTF-16 LE"),
            (.utf16BigEndian, [0xFE, 0xFF], "UTF-16 BE"),
            (.utf32LittleEndian, [0xFF, 0xFE, 0, 0], "UTF-32 LE"),
            (.utf32BigEndian, [0, 0, 0xFE, 0xFF], "UTF-32 BE"),
        ]
        for (encoding, bom, name) in encodings {
            let data = Data(bom) + (try XCTUnwrap(text.data(using: encoding)))
            let complete = try load(data, policy: .verifiedUnicode)
            XCTAssertEqual(complete.text, text)
            XCTAssertEqual(complete.encoding, name)
            XCTAssertNil(complete.warning)
            for limit in 1...20 {
                let prefix = try load(data, limit: limit, policy: .verifiedUnicode)
                XCTAssertEqual(prefix.encoding, name)
                XCTAssertTrue(prefix.truncated)
                XCTAssertTrue(text.hasPrefix(prefix.text))
                XCTAssertFalse(prefix.text.contains("�"))
                XCTAssertLessThanOrEqual(prefix.bytesRead, limit + 4)
            }
        }
    }

    func testVerifiedUnicodeUTF8TruncationKeepsACompletePrefix() throws {
        let text = "a🧭中文后续内容"
        for limit in 1...10 {
            let result = try load(Data(text.utf8), limit: limit, policy: .verifiedUnicode)
            XCTAssertTrue(result.truncated)
            XCTAssertTrue(text.hasPrefix(result.text))
            XCTAssertFalse(result.text.contains("�"))
            XCTAssertEqual(result.encoding, "UTF-8")
            XCTAssertLessThanOrEqual(result.bytesRead, limit + 4)
        }
    }

    func testVerifiedUnicodeRejectsBOMlessUTF16AndLegacyBytes() throws {
        let text = "server.name = 中文服务器\nenabled = true\nport = 8080\n"
        for encoding in [String.Encoding.utf16LittleEndian, .utf16BigEndian] {
            let data = try XCTUnwrap(text.data(using: encoding))
            XCTAssertEqual(try load(data).text, text)
            XCTAssertThrowsError(try load(data, policy: .verifiedUnicode))
        }
        let legacyText = String(repeating: "应用名称=轻量文档预览\n说明=检查中文配置文件编码，支持日志和源代码。\n", count: 6)
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let legacy = try XCTUnwrap(legacyText.data(using: gb18030))
        XCTAssertEqual(try load(legacy).text, legacyText)
        XCTAssertThrowsError(try load(legacy, policy: .verifiedUnicode))
    }

    func testVerifiedUnicodeRejectsOpaqueBytesThatLegacyDetectionCanDecode() throws {
        let opaque = Data(Array(repeating: [UInt8(0xA1), 0xB1, 0xC1, 0xD1, 0xE1, 0xF1], count: 100).flatMap { $0 })
        XCTAssertThrowsError(try load(opaque, policy: .verifiedUnicode)) { error in
            guard case TextLoaderError.unsupportedEncoding = error else {
                return XCTFail("Expected unsupported encoding, got \(error)")
            }
        }
    }

    func testVerifiedUnicodeDoesNotRepairInternalCorruptionOrIgnoreBinarySignatures() throws {
        let corruptUTF8 = Data("start".utf8) + Data([0xFF]) + Data("trailing text continues".utf8)
        XCTAssertThrowsError(try load(corruptUTF8, limit: 12, policy: .verifiedUnicode))
        XCTAssertThrowsError(try load(Data([0xFF, 0xFE, 0x41]), policy: .verifiedUnicode))
        XCTAssertThrowsError(try load(Data([0xEF, 0xBB, 0xBF, 0xFF]), policy: .verifiedUnicode))
        XCTAssertThrowsError(try load(Data("%PDF-1.4\nASCII payload".utf8), policy: .verifiedUnicode))
        XCTAssertThrowsError(try load(Data([0x01, 0x02, 0x00, 0x15, 0x07]), policy: .verifiedUnicode))
    }
}
