import Darwin
import Foundation

/// Locates the account's home for a folder picker without granting file access.
public enum UserHomeDirectory {
    public static func current() -> URL? {
        let userID = getuid()
        for size in [16 * 1024, 32 * 1024, 64 * 1024] {
            var entry = passwd()
            var result: UnsafeMutablePointer<passwd>?
            var path: String?
            var buffer = [CChar](repeating: 0, count: size)
            let status = buffer.withUnsafeMutableBufferPointer { storage in
                let status = getpwuid_r(userID, &entry, storage.baseAddress, storage.count, &result)
                if status == 0, let result, result.pointee.pw_uid == userID,
                   let directory = result.pointee.pw_dir {
                    path = String(validatingUTF8: directory)
                }
                return status
            }
            if status == ERANGE { continue }
            guard status == 0 else { return nil }
            return url(forAccountHomePath: path)
        }
        return nil
    }

    static func url(forAccountHomePath path: String?) -> URL? {
        guard let path, path.hasPrefix("/"), !path.contains("\0") else { return nil }
        // Check equivalent root paths lexically; no filesystem access is needed
        // before the user confirms the picker and supplies a security-scoped URL.
        var depth = 0
        for component in path.split(separator: "/") {
            if component == "." { continue }
            if component == ".." { depth = max(0, depth - 1) }
            else { depth += 1 }
        }
        guard depth > 0 else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
