import Foundation

enum HostImageAccessTarget {
    static func applicationURL(for bundleURL: URL) -> URL? {
        guard bundleURL.isFileURL else { return nil }
        if bundleURL.pathExtension == "app" { return bundleURL }
        guard bundleURL.pathExtension == "appex" else { return nil }
        let plugins = bundleURL.deletingLastPathComponent()
        let contents = plugins.deletingLastPathComponent()
        let application = contents.deletingLastPathComponent()
        guard plugins.lastPathComponent == "PlugIns", contents.lastPathComponent == "Contents",
              application.pathExtension == "app" else { return nil }
        return application
    }
}
