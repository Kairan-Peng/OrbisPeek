import Foundation

public enum LocalResourceError: LocalizedError {
    case outsideDocument, unsupportedImage, tooLarge, notFile

    public var errorDescription: String? {
        switch self {
        case .outsideDocument: return "The image must be inside the document's folder."
        case .unsupportedImage: return "Only local raster images are previewed."
        case .tooLarge: return "The image exceeds the 8 MiB preview limit."
        case .notFile: return "The image is not a regular file."
        }
    }
}

/// The renderer and native resource handler both enforce this boundary.
public enum LocalResourcePolicy {
    public static let maximumImageBytes = 8 * 1024 * 1024
    public static let imageMIMETypes = [
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
        "gif": "image/gif", "webp": "image/webp", "heic": "image/heic",
        "heif": "image/heif", "bmp": "image/bmp", "tif": "image/tiff", "tiff": "image/tiff",
    ]

    public static func resolve(relativePath: String, documentURL: URL) throws -> URL {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"),
              !relativePath.contains("\\"), !relativePath.contains("\0"),
              !relativePath.split(separator: "/").contains("..") else {
            throw LocalResourceError.outsideDocument
        }
        let root = documentURL.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        let candidate = root.appendingPathComponent(relativePath).resolvingSymlinksInPath().standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/") else {
            throw LocalResourceError.outsideDocument
        }
        guard imageMIMETypes[candidate.pathExtension.lowercased()] != nil else {
            throw LocalResourceError.unsupportedImage
        }
        let values = try candidate.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw LocalResourceError.notFile }
        guard (values.fileSize ?? .max) <= maximumImageBytes else { throw LocalResourceError.tooLarge }
        return candidate
    }
}
