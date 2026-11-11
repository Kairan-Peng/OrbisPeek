// Type associations adapted from FreeLook's UTIMapper.swift and Info.plist.
// Copyright (c) 2026 Neo Lee. Used under the MIT License.
// Upstream: neolee/freelook, d3f002589917f51279b49ea8b12b3bb343dd82dc.
// See THIRD_PARTY_NOTICES.md for the retained license and modifications.

import Foundation

public struct PreviewFileType: Codable, Sendable, Equatable {
    public let id: String
    public let language: String
    public let mode: String
    public let extensions: [String]
    public let filenames: [String]
    public let utis: [String]

    public init(id: String, language: String, mode: String, extensions: [String], filenames: [String], utis: [String]) {
        self.id = id
        self.language = language
        self.mode = mode
        self.extensions = extensions
        self.filenames = filenames
        self.utis = utis
    }
}

public enum FileTypeRegistry {
    /// Rendering recognition and Quick Look routing are separate capabilities.
    /// The bundled manifest also drives the generated extension Info.plist.
    public static let all: [PreviewFileType] = {
        guard let url = Bundle.module.url(forResource: "file-types", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let types = try? JSONDecoder().decode([PreviewFileType].self, from: data) else {
            preconditionFailure("The bundled file type manifest is missing or invalid.")
        }
        return types
    }()

    public static var supportedExtensions: [String] {
        Array(Set(all.flatMap(\.extensions))).sorted()
    }

    public static var supportedUTIs: [String] {
        Array(Set(all.flatMap(\.utis))).sorted()
    }

    private static let filenameMap: [String: PreviewFileType] = all.reduce(into: [:]) { result, type in
        for filename in type.filenames {
            result[filename.lowercased()] = type
        }
    }

    private static let extensionMap: [String: PreviewFileType] = all.reduce(into: [:]) { result, type in
        for suffix in type.extensions {
            result[suffix.lowercased()] = type
        }
    }

    public static func classify(fileName: String) -> PreviewFileType? {
        let filename = (fileName as NSString).lastPathComponent.lowercased()
        if let type = filenameMap[filename] {
            return type
        }
        if filename.hasPrefix(".env."), let type = extensionMap["env"] {
            return type
        }
        if filename.hasPrefix("dockerfile.") || filename.hasPrefix("containerfile.") {
            return all.first { $0.id == "dockerfile" }
        }
        return extensionMap[(filename as NSString).pathExtension]
    }
}
