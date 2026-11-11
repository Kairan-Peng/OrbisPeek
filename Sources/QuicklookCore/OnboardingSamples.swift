import Foundation

/// Exports small, offline documents so system Quick Look previews real files,
/// rather than reading the renderer's bundle directly.
public enum OnboardingSamples {
    public static let previewFileNames = [
        "quicklook-sample.md", "quicklook-sample.json",
        "quicklook-sample.jsonl", "quicklook-sample.toml",
    ]

    private static let allFileNames = previewFileNames + ["quicklook-sample.png"]
    private static let lock = NSLock()

    /// Explicit verification uses new URLs so Quick Look cannot satisfy the check
    /// solely by reusing a previous preview cached for the stable sample URL.
    public static func prepare(freshForVerification: Bool = false) throws -> [URL] {
        let cache = try FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return try prepare(
            in: cache.appendingPathComponent("Quicklook Preview Samples", isDirectory: true),
            freshForVerification: freshForVerification
        )
    }

    static func prepare(in root: URL, freshForVerification: Bool = false) throws -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        let manager = FileManager.default
        let resources = try allFileNames.map { name -> (String, Data) in
            guard let source = Bundle.module.url(forResource: name, withExtension: nil)
                    ?? Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "OnboardingSamples") else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: name])
            }
            return (name, try Data(contentsOf: source))
        }
        if manager.fileExists(atPath: root.path),
           try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
            throw CocoaError(.fileWriteNoPermission)
        }
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let preferred = root.appendingPathComponent("v1", isDirectory: true)
        let directory: URL
        if freshForVerification {
            directory = root.appendingPathComponent("v1-check-\(UUID().uuidString)", isDirectory: true)
        } else if manager.fileExists(atPath: preferred.path) {
            let isDirectory = try preferred.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let matches = isDirectory.isDirectory == true && isDirectory.isSymbolicLink != true
                && resources.allSatisfy { name, data in
                    let destination = preferred.appendingPathComponent(name)
                    guard let info = try? destination.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                          info.isRegularFile == true, info.isSymbolicLink != true,
                          info.fileSize == data.count else { return false }
                    return (try? Data(contentsOf: destination)) == data
                }
            if matches { return previewFileNames.map { preferred.appendingPathComponent($0) } }
            directory = root.appendingPathComponent("v1-\(UUID().uuidString)", isDirectory: true)
        } else {
            directory = preferred
        }
        try manager.createDirectory(at: directory, withIntermediateDirectories: false)
        for (name, data) in resources {
            try data.write(to: directory.appendingPathComponent(name), options: [.withoutOverwriting])
        }
        return previewFileNames.map { directory.appendingPathComponent($0) }
    }
}
