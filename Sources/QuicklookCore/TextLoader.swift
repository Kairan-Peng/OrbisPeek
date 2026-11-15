// Adapted from FreeLook FileLoader.swift (d3f002589917f51279b49ea8b12b3bb343dd82dc)
// and QLStephenSwift FileAnalyzer.swift (01125eb446266b235f5ea307e99bd3dfe3a575da).
// Copyright (c) 2026 Neo Lee. Copyright (c) 2025 Takashi Mochizuki.
// Both upstream projects are MIT licensed; see THIRD_PARTY_NOTICES.md.

import CoreFoundation
import Foundation

public struct LoadedText: Codable, Sendable {
    public let text: String
    public let encoding: String
    public let totalBytes: Int64
    public let bytesRead: Int
    public let truncated: Bool
    public let warning: String?
}

public enum TextDecodingPolicy: Sendable, Equatable {
    case automatic
    /// Accept UTF-8 or an explicit Unicode BOM without inferring an encoding.
    case verifiedUnicode
}

public enum TextLoaderError: LocalizedError {
    case invalidLimit
    case notRegularFile
    case binaryContent
    case unsupportedEncoding

    public var errorDescription: String? {
        switch self {
        case .invalidLimit:
            "The preview byte limit must be positive."
        case .notRegularFile:
            "Only regular text files can be previewed."
        case .binaryContent:
            "This file contains binary data rather than readable text."
        case .unsupportedEncoding:
            "The text encoding could not be decoded without losing characters."
        }
    }
}

public enum TextLoader {
    public static let defaultLimit = 512 * 1024

    /// Reads a bounded prefix, with at most four lookahead bytes for encoding boundaries.
    public static func load(url: URL, limit: Int = defaultLimit,
                            decodingPolicy: TextDecodingPolicy = .automatic) throws -> LoadedText {
        guard limit > 0, limit <= Int.max - 4 else { throw TextLoaderError.invalidLimit }

        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw TextLoaderError.notRegularFile }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let rawData = try handle.read(upToCount: limit + 4) ?? Data()
        let totalBytes = Int64(values.fileSize ?? rawData.count)
        let truncated = rawData.count > limit || totalBytes > Int64(rawData.count)

        guard !rawData.isEmpty else {
            return LoadedText(text: "", encoding: "UTF-8", totalBytes: totalBytes,
                              bytesRead: 0, truncated: false, warning: nil)
        }

        // BOMs and the UTF-16 byte pattern must be considered before NUL detection.
        let selection = try selectEncoding(data: rawData, incompleteTail: truncated, policy: decodingPolicy)
        let preview = Data(rawData.prefix(limit).dropFirst(min(selection.bomBytes, limit)))
        guard let text = decode(preview, as: selection.encoding, incompleteTail: truncated) else {
            throw TextLoaderError.unsupportedEncoding
        }
        guard !looksBinary(text) else { throw TextLoaderError.binaryContent }

        return LoadedText(
            text: text,
            encoding: selection.name,
            totalBytes: totalBytes,
            bytesRead: rawData.count,
            truncated: truncated,
            warning: selection.inferred
                ? "Encoding automatically inferred as \(selection.name). Check the text if characters look incorrect."
                : nil
        )
    }

    private struct EncodingSelection {
        let encoding: String.Encoding
        let name: String
        let bomBytes: Int
        let inferred: Bool
    }

    private static func selectEncoding(data: Data, incompleteTail: Bool,
                                       policy: TextDecodingPolicy) throws -> EncodingSelection {
        if let bom = detectBOM(data) {
            let body = Data(data.dropFirst(bom.bomBytes))
            guard let text = decode(body, as: bom.encoding, incompleteTail: incompleteTail),
                  !looksBinary(text) else { throw TextLoaderError.unsupportedEncoding }
            return bom
        }

        guard !hasBinarySignature(data) else { throw TextLoaderError.binaryContent }

        if case .automatic = policy, let utf16 = detectBOMlessUTF16(data),
           let text = decode(data, as: utf16.encoding, incompleteTail: incompleteTail),
           !looksBinary(text) {
            return utf16
        }

        guard !looksBinary(data) else { throw TextLoaderError.binaryContent }

        // ISO-2022-JP consists of ASCII bytes, so its escape markers precede UTF-8.
        if case .automatic = policy, hasISO2022JPEscapeSequence(data),
           decode(data, as: .iso2022JP, incompleteTail: incompleteTail) != nil {
            return EncodingSelection(encoding: .iso2022JP, name: "ISO-2022-JP", bomBytes: 0, inferred: true)
        }

        if decode(data, as: .utf8, incompleteTail: incompleteTail) != nil {
            return EncodingSelection(encoding: .utf8, name: "UTF-8", bomBytes: 0, inferred: false)
        }

        guard case .automatic = policy else { throw TextLoaderError.unsupportedEncoding }

        // Reuse Apple's statistical detector, rather than assigning a regional encoding
        // to every byte sequence that happens to decode. Legacy results remain guesses.
        if let encoding = detectWithFoundation(data),
           let text = decode(data, as: encoding, incompleteTail: incompleteTail),
           !looksBinary(text) {
            return EncodingSelection(encoding: encoding, name: name(for: encoding), bomBytes: 0, inferred: true)
        }
        throw TextLoaderError.unsupportedEncoding
    }

    private static func detectBOM(_ data: Data) -> EncodingSelection? {
        let marks: [(bytes: [UInt8], encoding: String.Encoding, name: String)] = [
            ([0x00, 0x00, 0xFE, 0xFF], .utf32BigEndian, "UTF-32 BE"),
            ([0xFF, 0xFE, 0x00, 0x00], .utf32LittleEndian, "UTF-32 LE"),
            ([0xEF, 0xBB, 0xBF], .utf8, "UTF-8 BOM"),
            ([0xFE, 0xFF], .utf16BigEndian, "UTF-16 BE"),
            ([0xFF, 0xFE], .utf16LittleEndian, "UTF-16 LE")
        ]
        for mark in marks where data.starts(with: mark.bytes) {
            return EncodingSelection(encoding: mark.encoding, name: mark.name,
                                     bomBytes: mark.bytes.count, inferred: false)
        }
        return nil
    }

    private static func detectBOMlessUTF16(_ data: Data) -> EncodingSelection? {
        let sample = data.prefix(8192)
        let pairs = sample.count / 2
        guard pairs >= 2 else { return nil }
        var evenZeros = 0
        var oddZeros = 0
        for index in 0..<(pairs * 2) where sample[index] == 0 {
            if index.isMultiple(of: 2) { evenZeros += 1 } else { oddZeros += 1 }
        }
        let evenRatio = Double(evenZeros) / Double(pairs)
        let oddRatio = Double(oddZeros) / Double(pairs)
        if oddRatio >= 0.3, evenRatio <= 0.05 {
            return EncodingSelection(encoding: .utf16LittleEndian, name: "UTF-16 LE", bomBytes: 0, inferred: true)
        }
        if evenRatio >= 0.3, oddRatio <= 0.05 {
            return EncodingSelection(encoding: .utf16BigEndian, name: "UTF-16 BE", bomBytes: 0, inferred: true)
        }
        return nil
    }

    private static func decode(_ data: Data, as encoding: String.Encoding, incompleteTail: Bool) -> String? {
        if let text = decodeComplete(data, as: encoding) { return text }
        guard incompleteTail, !data.isEmpty else { return nil }
        // UTF-8/GB18030/UTF-32 need at most three trailing bytes removed;
        // UTF-16 may additionally end at a high surrogate. Never repair internal bytes.
        for removed in 1...min(3, data.count) {
            if let text = decodeComplete(Data(data.dropLast(removed)), as: encoding) { return text }
        }
        return nil
    }

    private static func decodeComplete(_ data: Data, as encoding: String.Encoding) -> String? {
        let isUTF16 = encoding == .utf16LittleEndian || encoding == .utf16BigEndian
        let isUTF32 = encoding == .utf32LittleEndian || encoding == .utf32BigEndian
        // Foundation may silently discard an incomplete final UTF-16 unit. Check the
        // byte count and round trip for these codecs so only deliberate truncation repairs it.
        if isUTF16, !data.count.isMultiple(of: 2) { return nil }
        if isUTF32, !data.count.isMultiple(of: 4) { return nil }
        guard let text = String(data: data, encoding: encoding) else { return nil }
        if isUTF16 || isUTF32 {
            guard text.data(using: encoding) == data else { return nil }
        }
        return text
    }

    private static func detectWithFoundation(_ data: Data) -> String.Encoding? {
        let candidates: [String.Encoding] = [
            cfEncoding(.GB_18030_2000), cfEncoding(.big5), .shiftJIS,
            .japaneseEUC, cfEncoding(.EUC_KR), .windowsCP1252, .isoLatin1
        ]
        var converted: NSString?
        var lossy = ObjCBool(false)
        let value = NSString.stringEncoding(
            for: data,
            encodingOptions: [
                .allowLossyKey: false,
                .suggestedEncodingsKey: candidates.map { NSNumber(value: $0.rawValue) }
            ],
            convertedString: &converted,
            usedLossyConversion: &lossy
        )
        guard value != 0, !lossy.boolValue else { return nil }
        return String.Encoding(rawValue: value)
    }

    private static func cfEncoding(_ encoding: CFStringEncodings) -> String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(encoding.rawValue)))
    }

    private static func name(for encoding: String.Encoding) -> String {
        let known: [(String.Encoding, String)] = [
            (.utf8, "UTF-8"), (.utf16, "UTF-16"), (.utf16LittleEndian, "UTF-16 LE"),
            (.utf16BigEndian, "UTF-16 BE"), (.shiftJIS, "Shift-JIS"), (.japaneseEUC, "EUC-JP"),
            (.windowsCP1252, "Windows-1252"), (.isoLatin1, "ISO-8859-1"),
            (cfEncoding(.GB_18030_2000), "GB18030"), (cfEncoding(.GB_2312_80), "GB2312"),
            (cfEncoding(.big5), "Big5"), (cfEncoding(.EUC_KR), "EUC-KR")
        ]
        return known.first(where: { $0.0 == encoding })?.1 ?? String.localizedName(of: encoding)
    }

    private static func looksBinary(_ data: Data) -> Bool {
        let sample = data.prefix(8192)
        guard !sample.isEmpty else { return false }
        if data.contains(0) { return true }
        let suspicious = sample.reduce(0) { count, byte in
            count + ((byte < 0x20 && ![0x09, 0x0A, 0x0C, 0x0D, 0x1B].contains(byte)) || byte == 0x7F ? 1 : 0)
        }
        return Double(suspicious) / Double(sample.count) > 0.3
    }

    private static func looksBinary(_ text: String) -> Bool {
        let sample = text.unicodeScalars.prefix(8192)
        guard !sample.isEmpty else { return false }
        if text.unicodeScalars.contains(where: { $0.value == 0 }) { return true }
        let suspicious = sample.reduce(0) { count, scalar in
            let value = scalar.value
            return count + (((value < 0x20 && ![0x09, 0x0A, 0x0C, 0x0D, 0x1B].contains(value))
                || (0x7F...0x9F).contains(value)) ? 1 : 0)
        }
        return Double(suspicious) / Double(sample.count) > 0.3
    }

    private static func hasBinarySignature(_ data: Data) -> Bool {
        let signatures: [[UInt8]] = [
            [0x89, 0x50, 0x4E, 0x47], [0xFF, 0xD8, 0xFF], [0x47, 0x49, 0x46, 0x38],
            [0x50, 0x4B, 0x03, 0x04], [0x7F, 0x45, 0x4C, 0x46], [0x25, 0x50, 0x44, 0x46],
            [0xCF, 0xFA, 0xED, 0xFE], [0xFE, 0xED, 0xFA, 0xCF], [0xCA, 0xFE, 0xBA, 0xBE]
        ]
        return signatures.contains { data.starts(with: $0) }
    }

    private static func hasISO2022JPEscapeSequence(_ data: Data) -> Bool {
        guard data.count >= 3 else { return false }
        for index in 0..<(data.count - 2) where data[index] == 0x1B {
            if data[index + 1] == 0x24, [0x40, 0x42].contains(data[index + 2]) { return true }
            if data[index + 1] == 0x28, [0x42, 0x4A, 0x49].contains(data[index + 2]) { return true }
        }
        return false
    }
}
