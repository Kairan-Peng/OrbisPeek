import CryptoKit
import Foundation
import OSLog

/// A short-lived, explicit sample check, not passive logging of user documents.
public enum PreviewVerification {
    public struct Request: Codable, Sendable {
        public let id: UUID
        public let filePath: String
        public let createdAt: Date
    }

    public struct Receipt: Codable, Sendable {
        public let requestID: UUID
        public let filePath: String
        public let extensionIdentifier: String
        public let extensionPath: String
        public let version: String
        public let build: String
        public let mode: String
        /// The host's local receipt time, not the extension's render timestamp.
        public let completedAt: Date
    }

    private struct Proof: Encodable {
        let requestID: UUID
        let filePath: String
        let extensionIdentifier: String
        let extensionPath: String
        let version: String
        let build: String
        let mode: String
    }

    static let receiptNotificationName = Notification.Name("org.quicklook.preview.sample-rendered.v1")
    private static let lifetime: TimeInterval = 120
    private static let maximumRecordBytes = 16 * 1024
    private static let requestName = "Quicklook.samplePreview.request.v1"
    private static let logger = Logger(subsystem: "org.quicklook.preview", category: "SampleVerification")

    public static var isAvailable: Bool { groupIdentifier != nil }

    public static func begin(fileURL: URL) throws -> Request {
        try begin(fileURL: fileURL, in: preferences(), now: Date())
    }

    public static func end(_ request: Request) {
        guard let store = try? preferences() else { return }
        end(request, in: store)
    }

    /// Register before showing Quick Look. The handler runs at most once on the
    /// main run loop. Retain the returned observer until the check ends.
    public static func observeReceipt(
        for request: Request, expectedExtensionURL: URL, version: String, build: String,
        handler: @escaping (Receipt) -> Void
    ) -> NSObjectProtocol {
        ReceiptObserver(
            request: request, expectedExtensionURL: expectedExtensionURL, version: version, build: build,
            store: try? preferences(), handler: handler
        )
    }

    public static func removeReceiptObserver(_ observer: NSObjectProtocol) {
        (observer as? ReceiptObserver)?.stop()
    }

    static func observeReceipt(
        for request: Request, expectedExtensionURL: URL, version: String, build: String,
        in store: UserDefaults, handler: @escaping (Receipt) -> Void
    ) -> NSObjectProtocol {
        ReceiptObserver(
            request: request, expectedExtensionURL: expectedExtensionURL, version: version, build: build,
            store: store, handler: handler
        )
    }

    /// Capture the nonce before rendering, so an old render cannot satisfy a retry.
    public static func pendingRequest(for fileURL: URL) -> Request? {
        guard let store = try? preferences(),
              let request = pendingRequest(for: fileURL, in: store, now: Date()) else { return nil }
        logger.notice("Sample prepare matched the active request")
        return request
    }

    public static func observeRenderCompletion(fileURL: URL, succeeded: Bool) {
        guard let store = try? preferences(),
              pendingRequest(for: fileURL, in: store, now: Date()) != nil else { return }
        logger.notice("Sample renderer completed: \(succeeded, privacy: .public)")
    }

    public static func diagnosticSummary() -> [String: String] {
        guard let store = try? preferences() else { return ["sharedPreferences": "unavailable"] }
        var summary = ["sharedPreferences": "available", "receiptChannel": "distributed-notification"]
        if let request: Request = read(requestName, in: store) {
            summary["requestID"] = request.id.uuidString
            summary["requestedFile"] = request.filePath
            summary["requestAgeSeconds"] = String(Int(Date().timeIntervalSince(request.createdAt)))
        } else {
            do { let _: Request = try readRecord(requestName, in: store) }
            catch { summary["requestReadError"] = error.localizedDescription }
        }
        return summary
    }

    /// Only the extension calls this after its own WebKit renderer completes.
    /// Quick Look can read the App Group request but cannot write group receipts.
    public static func recordRenderedSample(fileURL: URL, mode: String, request: Request) {
        guard Bundle.main.bundleIdentifier == ExtensionDiagnostics.extensionIdentifier,
              let store = try? preferences(),
              let token = renderedSampleToken(
                fileURL: fileURL, mode: mode, request: request, in: store, now: Date(),
                identifier: Bundle.main.bundleIdentifier ?? "",
                extensionPath: Bundle.main.bundleURL.standardizedFileURL.path,
                version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
              ) else { return }
        // Sandboxed distributed notifications must not carry a userInfo dictionary.
        // The object contains only a digest, never the nonce or document path.
        DistributedNotificationCenter.default().postNotificationName(
            receiptNotificationName, object: token, userInfo: nil, deliverImmediately: true
        )
        logger.notice("Sample render receipt notification posted")
    }

    static func begin(fileURL: URL, in store: UserDefaults, now: Date) throws -> Request {
        guard fileURL.isFileURL, expectedMode(for: fileURL.path) != nil else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let request = Request(id: UUID(), filePath: fileURL.standardizedFileURL.path, createdAt: now)
        let data = try JSONEncoder().encode(request)
        guard data.count <= maximumRecordBytes else { throw CocoaError(.fileWriteOutOfSpace) }
        // Only the host writes shared preferences; the extension reads this key.
        store.set(data, forKey: requestName)
        return request
    }

    static func pendingRequest(for fileURL: URL, in store: UserDefaults, now: Date) -> Request? {
        guard fileURL.isFileURL, let request: Request = read(requestName, in: store),
              valid(request, now: now), request.filePath == fileURL.standardizedFileURL.path else { return nil }
        return request
    }

    static func renderedSampleToken(
        fileURL: URL, mode: String, request: Request, in store: UserDefaults, now: Date,
        identifier: String, extensionPath: String, version: String, build: String
    ) -> String? {
        guard identifier == ExtensionDiagnostics.extensionIdentifier,
              expectedMode(for: request.filePath) == mode,
              let current = pendingRequest(for: fileURL, in: store, now: now),
              matches(current, request), valid(request, now: now) else { return nil }
        return proofToken(
            request: request, extensionPath: extensionPath, identifier: identifier,
            version: version, build: build, mode: mode
        )
    }

    static func receipt(
        matching token: String, for request: Request, expectedExtensionURL: URL,
        version: String, build: String, in store: UserDefaults, now: Date
    ) -> Receipt? {
        guard valid(request, now: now),
              let current: Request = read(requestName, in: store), matches(current, request),
              expectedExtensionURL.isFileURL, let mode = expectedMode(for: request.filePath),
              token == proofToken(
                request: request, extensionPath: expectedExtensionURL.standardizedFileURL.path,
                identifier: ExtensionDiagnostics.extensionIdentifier, version: version, build: build, mode: mode
              ) else { return nil }
        return Receipt(
            requestID: request.id, filePath: request.filePath,
            extensionIdentifier: ExtensionDiagnostics.extensionIdentifier,
            extensionPath: expectedExtensionURL.standardizedFileURL.path,
            version: version, build: build, mode: mode, completedAt: now
        )
    }

    static func end(_ request: Request, in store: UserDefaults) {
        guard let current: Request = read(requestName, in: store), matches(current, request) else { return }
        store.removeObject(forKey: requestName)
    }

    private static func proofToken(
        request: Request, extensionPath: String, identifier: String, version: String, build: String, mode: String
    ) -> String? {
        guard extensionPath.hasPrefix("/"), !version.isEmpty, !build.isEmpty else { return nil }
        let proof = Proof(
            requestID: request.id, filePath: request.filePath, extensionIdentifier: identifier,
            extensionPath: URL(fileURLWithPath: extensionPath).standardizedFileURL.path,
            version: version, build: build, mode: mode
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(proof), data.count <= maximumRecordBytes else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func expectedMode(for path: String) -> String? {
        switch URL(fileURLWithPath: path).lastPathComponent {
        case "orbispeek-sample.md": return "markdown"
        case "orbispeek-sample.json": return "json"
        case "orbispeek-sample.jsonl": return "jsonl"
        case "orbispeek-sample.toml": return "code"
        default: return nil
        }
    }

    private static func valid(_ request: Request, now: Date) -> Bool {
        let age = now.timeIntervalSince(request.createdAt)
        return age >= 0 && age <= lifetime && request.filePath.hasPrefix("/")
            && expectedMode(for: request.filePath) != nil
    }

    private static func matches(_ lhs: Request, _ rhs: Request) -> Bool {
        lhs.id == rhs.id && lhs.filePath == rhs.filePath && lhs.createdAt == rhs.createdAt
    }

    private static var groupIdentifier: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "QuicklookAppGroup") as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func preferences() throws -> UserDefaults {
        guard let identifier = groupIdentifier, let store = UserDefaults(suiteName: identifier) else {
            throw DirectoryAccessError.sharedContainerUnavailable
        }
        return store
    }

    private static func read<T: Decodable>(_ key: String, in store: UserDefaults) -> T? {
        try? readRecord(key, in: store)
    }

    private static func readRecord<T: Decodable>(_ key: String, in store: UserDefaults) throws -> T {
        guard let data = store.data(forKey: key) else { throw CocoaError(.fileNoSuchFile) }
        guard data.count <= maximumRecordBytes else { throw CocoaError(.fileReadTooLarge) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private final class ReceiptObserver: NSObject {
        let request: Request
        let expectedExtensionURL: URL
        let version: String
        let build: String
        let store: UserDefaults?
        let handler: (Receipt) -> Void
        private var stopped = false

        init(request: Request, expectedExtensionURL: URL, version: String, build: String,
             store: UserDefaults?, handler: @escaping (Receipt) -> Void) {
            self.request = request
            self.expectedExtensionURL = expectedExtensionURL
            self.version = version
            self.build = build
            self.store = store
            self.handler = handler
            super.init()
            DistributedNotificationCenter.default().addObserver(
                self, selector: #selector(receive(_:)), name: receiptNotificationName,
                object: nil, suspensionBehavior: .deliverImmediately
            )
        }

        @objc private func receive(_ notification: Notification) {
            guard !stopped, let store, let token = notification.object as? String,
                  let receipt = PreviewVerification.receipt(
                    matching: token, for: request, expectedExtensionURL: expectedExtensionURL,
                    version: version, build: build, in: store, now: Date()
                  ) else { return }
            stop()
            handler(receipt)
        }

        func stop() {
            guard !stopped else { return }
            stopped = true
            DistributedNotificationCenter.default().removeObserver(self, name: receiptNotificationName, object: nil)
        }

        deinit { stop() }
    }
}
