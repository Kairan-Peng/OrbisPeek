import Foundation

public enum PreviewPreferencesError: LocalizedError {
    case unavailable
    case sharedContainerUnavailable
    case invalidStore

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "此版本不支持共享预览设置。"
        case .sharedContainerUnavailable:
            "无法保存预览设置。请重新打开应用后再试。"
        case .invalidStore:
            "预览设置文件不可用。"
        }
    }
}

/// Each preview reads the atomically replaced file, without process-local
/// preference caching. Missing or unreadable settings always keep opt-in off.
public enum PreviewPreferences {
    private static let lock = NSLock()
    private static let maximumStoreBytes = 4096

    private struct Store: Codable {
        let version: Int
        let unclassifiedTextEnabled: Bool
    }

    private static var groupIdentifier: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "QuicklookAppGroup") as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Checks configuration without requesting access to the shared container.
    public static var isAvailable: Bool { groupIdentifier != nil }

    public static var unclassifiedTextEnabled: Bool {
        guard let url = try? sharedStoreURL() else { return false }
        return readUnclassifiedTextEnabled(at: url)
    }

    public static func setUnclassifiedTextEnabled(_ enabled: Bool) throws {
        try setUnclassifiedTextEnabled(enabled, storeURL: sharedStoreURL())
    }

    private static func sharedStoreURL() throws -> URL {
        guard let groupIdentifier else { throw PreviewPreferencesError.unavailable }
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            throw PreviewPreferencesError.sharedContainerUnavailable
        }
        return container.appendingPathComponent("preview-preferences-v1.json")
    }

    static func readUnclassifiedTextEnabled(at url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  (values.fileSize ?? .max) <= maximumStoreBytes else { return false }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: maximumStoreBytes + 1) ?? Data()
            guard data.count <= maximumStoreBytes else { return false }
            let store = try JSONDecoder().decode(Store.self, from: data)
            return store.version == 1 && store.unclassifiedTextEnabled
        } catch {
            return false
        }
    }

    static func setUnclassifiedTextEnabled(_ enabled: Bool, storeURL: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        if FileManager.default.fileExists(atPath: storeURL.path) {
            let values = try storeURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw PreviewPreferencesError.invalidStore
            }
        } else if (try? storeURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw PreviewPreferencesError.invalidStore
        }
        let data = try JSONEncoder().encode(Store(version: 1, unclassifiedTextEnabled: enabled))
        try data.write(to: storeURL, options: .atomic)
    }
}
