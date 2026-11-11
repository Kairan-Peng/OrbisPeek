import Foundation

public struct PreviewPayload: Codable, Sendable {
    public let fileName: String
    public let text: String
    public let language: String
    public let mode: String
    public let encoding: String
    public let totalBytes: Int64
    public let bytesRead: Int
    public let truncated: Bool
    public let warning: String?

    public static func load(url: URL, limit: Int = 524_288) throws -> PreviewPayload {
        let loaded = try TextLoader.load(url: url, limit: limit)
        let type = FileTypeRegistry.classify(fileName: url.lastPathComponent)
        return PreviewPayload(
            fileName: url.lastPathComponent, text: loaded.text,
            language: type?.language ?? "plaintext", mode: type?.mode ?? "code",
            encoding: loaded.encoding, totalBytes: loaded.totalBytes,
            bytesRead: loaded.bytesRead, truncated: loaded.truncated, warning: loaded.warning
        )
    }
}
