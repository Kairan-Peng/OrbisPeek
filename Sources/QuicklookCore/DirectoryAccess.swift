import Foundation

public enum DirectoryAccessError: LocalizedError {
    case unavailable
    case sharedContainerUnavailable
    case notDirectory
    case tooManyDirectories
    case invalidStoredGrants
    case oversizedBookmark

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "Folder access requires the optional signed App Group build. This build has no shared folder-access group."
        case .sharedContainerUnavailable:
            "The shared folder-access container is unavailable. Check the app and extension's App Group signing configuration."
        case .notDirectory:
            "Choose a local folder to allow its document images."
        case .tooManyDirectories:
            "Up to 32 folders can be authorized. Revoke existing folder access before adding more."
        case .invalidStoredGrants:
            "The saved folder-access list is invalid or exceeds its size limit. Revoke folder access and choose the folders again."
        case .oversizedBookmark:
            "The selected folder's access bookmark exceeds the supported size limit."
        }
    }
}

/// Keeps the process's directory sandbox extension alive while a preview uses it.
public final class DirectoryAccessScope: @unchecked Sendable {
    private let url: URL

    fileprivate init(url: URL) { self.url = url }

    deinit { url.stopAccessingSecurityScopedResource() }
}

/// A user-selected folder is handed off with an ephemeral bookmark. Each process
/// then persists its own explicit bookmark; explicit bookmarks are never shared.
public enum DirectoryAccess {
    private static let lock = NSLock()
    private static let maximumDirectories = 32
    private static let maximumBookmarkBytes = 32 * 1024
    private static let maximumStoreBytes = 2 * 1024 * 1024
    private static let activatedCacheKey = "Quicklook.directoryAccess.activatedBookmarks.v1"
    private static let hostCacheKey = "Quicklook.directoryAccess.hostBookmarks.v1"

    private struct Grant: Codable {
        let id: String
        let path: String
        var implicitBookmark: Data
    }

    private struct Store: Codable {
        let version: Int
        var grants: [Grant]

        static var empty: Store { Store(version: 1, grants: []) }
    }

    private static var groupIdentifier: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "QuicklookAppGroup") as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Checks build configuration without requesting access to a shared container.
    public static var isAvailable: Bool { groupIdentifier != nil }

    /// Call only with a directory URL selected by the user through NSOpenPanel.
    public static func grant(folderURL: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        let storeURL = try sharedStoreURL()
        let started = folderURL.startAccessingSecurityScopedResource()
        defer { if started { folderURL.stopAccessingSecurityScopedResource() } }

        guard folderURL.isFileURL else { throw DirectoryAccessError.notDirectory }
        let directory = canonical(folderURL)
        guard try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw DirectoryAccessError.notDirectory
        }
        var store = try readStore(at: storeURL)
        let previous = store.grants.first(where: { $0.path == directory.path })
        guard previous != nil || store.grants.count < maximumDirectories else {
            throw DirectoryAccessError.tooManyDirectories
        }

        let implicit = try directory.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let explicit = try directory.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil, relativeTo: nil
        )
        guard implicit.count <= maximumBookmarkBytes, explicit.count <= maximumBookmarkBytes else {
            throw DirectoryAccessError.oversizedBookmark
        }
        let grant = Grant(id: previous?.id ?? UUID().uuidString, path: directory.path, implicitBookmark: implicit)
        store.grants.removeAll { $0.id == grant.id }
        store.grants.append(grant)

        // Host-only explicit bookmarks allow the host to refresh handoffs after a
        // reboot. The extension has separate UserDefaults and never consumes these.
        var hostCache = readCache(key: hostCacheKey, validIDs: Set(store.grants.map(\.id)))
        hostCache[grant.id] = explicit
        UserDefaults.standard.set(hostCache, forKey: hostCacheKey)
        try writeStore(store, to: storeURL)
    }

    public static func revokeAll() throws {
        lock.lock()
        defer { lock.unlock() }
        // Atomically publishing an empty list invalidates every previous grant ID.
        // Other processes' caches cannot be used without a matching current ID.
        try writeStore(.empty, to: sharedStoreURL())
        UserDefaults.standard.removeObject(forKey: hostCacheKey)
        UserDefaults.standard.removeObject(forKey: activatedCacheKey)
    }

    /// Removing one folder does not disturb other grants. Existing previews keep
    /// their scope until closed; new previews must match the updated shared list.
    public static func revoke(folderURL: URL) throws {
        try revoke(folderURL: folderURL, storeURL: sharedStoreURL(), defaults: .standard)
    }

    static func revoke(folderURL: URL, storeURL: URL, defaults: UserDefaults) throws {
        lock.lock()
        defer { lock.unlock() }
        guard folderURL.isFileURL else { throw DirectoryAccessError.notDirectory }
        var store = try readStore(at: storeURL)
        // A listed folder may since have become a symlink. Remove that recorded
        // path first, rather than accidentally revoking its new destination.
        let requestedPath = folderURL.standardizedFileURL.path
        let path = store.grants.contains(where: { $0.path == requestedPath })
            ? requestedPath : canonical(folderURL).path
        let removedIDs = Set(store.grants.filter { $0.path == path }.map(\.id))
        guard !removedIDs.isEmpty else { return }
        store.grants.removeAll { removedIDs.contains($0.id) }
        // Publish revocation before touching local caches. Other processes reject
        // a removed ID even if their own explicit bookmark remains cached.
        try writeStore(store, to: storeURL)
        for key in [hostCacheKey, activatedCacheKey] {
            var cache = defaults.dictionary(forKey: key) ?? [:]
            for id in removedIDs { cache.removeValue(forKey: id) }
            defaults.set(cache, forKey: key)
        }
    }

    /// The host refreshes its ephemeral handoffs from its own persistent bookmarks.
    /// Extension processes have no host cache, so this remains a read there.
    public static func grantedPaths() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        guard let storeURL = try? sharedStoreURL(), var store = try? readStore(at: storeURL) else { return [] }
        refreshHostHandoffs(in: &store, at: storeURL)
        return store.grants.map(\.path).sorted()
    }

    /// Returns nil when there is no current matching grant or access is unavailable.
    /// The caller must retain the returned scope until all image reads have finished.
    public static func activate(for documentURL: URL) -> DirectoryAccessScope? {
        lock.lock()
        defer { lock.unlock() }
        guard documentURL.isFileURL,
              let storeURL = try? sharedStoreURL(),
              let store = try? readStore(at: storeURL) else { return nil }

        let validIDs = Set(store.grants.map(\.id))
        var cache = readCache(key: activatedCacheKey, validIDs: validIDs)
        defer { UserDefaults.standard.set(cache, forKey: activatedCacheKey) }
        let document = canonical(documentURL)
        let matching = store.grants.filter { isDescendant(document.path, of: $0.path) }
            .sorted { $0.path.count > $1.path.count }

        for grant in matching {
            if let data = cache[grant.id],
               let access = start(data: data, grant: grant, document: document, explicit: true) {
                if let renewed = access.renewedBookmark { cache[grant.id] = renewed }
                guard isCurrent(grant, at: storeURL) else { return nil }
                return access.scope
            }
            cache.removeValue(forKey: grant.id)

            guard let access = start(data: grant.implicitBookmark, grant: grant, document: document, explicit: false) else {
                continue
            }
            // Create this explicit bookmark in the receiving process. It has that
            // process's code identity, not the containing application's identity.
            if let explicit = try? access.url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil, relativeTo: nil
            ), explicit.count <= maximumBookmarkBytes {
                cache[grant.id] = explicit
            }
            guard isCurrent(grant, at: storeURL) else { return nil }
            return access.scope
        }
        return nil
    }

    private struct Access {
        let url: URL
        let scope: DirectoryAccessScope
        let renewedBookmark: Data?
    }

    private static func start(data: Data, grant: Grant, document: URL, explicit: Bool) -> Access? {
        guard !data.isEmpty, data.count <= maximumBookmarkBytes else { return nil }
        var stale = false
        let options: URL.BookmarkResolutionOptions = explicit
            ? [.withSecurityScope, .withoutUI]
            : [.withoutUI, .withoutImplicitStartAccessing]
        guard let url = try? URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { return nil }
        let scope = DirectoryAccessScope(url: url)

        // Do not let a moved bookmark, changed symlink, or prefix collision extend
        // the grant to a different directory than the one recorded by the host.
        guard canonical(url).path == grant.path,
              isDescendant(canonical(document).path, of: grant.path),
              (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }

        var renewed: Data?
        if explicit, stale {
            if let data = try? url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil, relativeTo: nil
            ), data.count <= maximumBookmarkBytes {
                renewed = data
            }
        }
        return Access(url: url, scope: scope, renewedBookmark: renewed)
    }

    private static func refreshHostHandoffs(in store: inout Store, at storeURL: URL) {
        let validIDs = Set(store.grants.map(\.id))
        var cache = readCache(key: hostCacheKey, validIDs: validIDs)
        guard !cache.isEmpty else { return }
        var changed = false
        for index in store.grants.indices {
            let grant = store.grants[index]
            // A synthetic child path checks the same boundary without reading a
            // document or enumerating files in the selected directory.
            let child = URL(fileURLWithPath: grant.path).appendingPathComponent(".quicklook-scope-check")
            guard let data = cache[grant.id],
                  let access = start(data: data, grant: grant, document: child, explicit: true) else { continue }
            if let renewed = access.renewedBookmark { cache[grant.id] = renewed }
            if let implicit = try? access.url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil),
               implicit.count <= maximumBookmarkBytes {
                store.grants[index].implicitBookmark = implicit
                changed = true
            }
            withExtendedLifetime(access.scope) {}
        }
        UserDefaults.standard.set(cache, forKey: hostCacheKey)
        if changed { try? writeStore(store, to: storeURL) }
    }

    private static func readCache(key: String, validIDs: Set<String>) -> [String: Data] {
        let raw = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        var result: [String: Data] = [:]
        for id in validIDs {
            if let data = raw[id] as? Data, !data.isEmpty, data.count <= maximumBookmarkBytes {
                result[id] = data
            }
        }
        return result
    }

    private static func sharedStoreURL() throws -> URL {
        guard let groupIdentifier else { throw DirectoryAccessError.unavailable }
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            throw DirectoryAccessError.sharedContainerUnavailable
        }
        return container.appendingPathComponent("directory-grants-v1.json")
    }

    private static func readStore(at url: URL) throws -> Store {
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? .max) <= maximumStoreBytes else { throw DirectoryAccessError.invalidStoredGrants }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumStoreBytes + 1) ?? Data()
        guard data.count <= maximumStoreBytes else { throw DirectoryAccessError.invalidStoredGrants }
        let store = try JSONDecoder().decode(Store.self, from: data)
        try validate(store)
        return store
    }

    private static func writeStore(_ store: Store, to url: URL) throws {
        try validate(store)
        if FileManager.default.fileExists(atPath: url.path),
           try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
            throw DirectoryAccessError.invalidStoredGrants
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(store)
        guard data.count <= maximumStoreBytes else { throw DirectoryAccessError.invalidStoredGrants }
        try data.write(to: url, options: [.atomic])
    }

    private static func validate(_ store: Store) throws {
        guard store.version == 1, store.grants.count <= maximumDirectories,
              Set(store.grants.map(\.id)).count == store.grants.count,
              Set(store.grants.map(\.path)).count == store.grants.count else {
            throw DirectoryAccessError.invalidStoredGrants
        }
        for grant in store.grants {
            guard UUID(uuidString: grant.id) != nil, grant.path.hasPrefix("/"),
                  !grant.path.contains("\0"), grant.path.utf8.count <= 4096,
                  URL(fileURLWithPath: grant.path).standardizedFileURL.path == grant.path,
                  !grant.implicitBookmark.isEmpty, grant.implicitBookmark.count <= maximumBookmarkBytes else {
                throw DirectoryAccessError.invalidStoredGrants
            }
        }
    }

    private static func isCurrent(_ grant: Grant, at url: URL) -> Bool {
        guard let store = try? readStore(at: url) else { return false }
        return store.grants.contains { $0.id == grant.id && $0.path == grant.path }
    }

    private static func canonical(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    private static func isDescendant(_ path: String, of directory: String) -> Bool {
        directory == "/" ? path != "/" : path.hasPrefix(directory + "/")
    }
}
