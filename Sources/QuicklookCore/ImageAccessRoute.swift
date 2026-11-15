import Foundation

/// An explicit preview action opens the host's folder-management page. The
/// route carries no document path, suggested folder, or authorization payload.
public enum ImageAccessRoute {
    public static let url = URL(string: "orbispeek://image-access")!

    public static func matches(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.scheme?.lowercased() == "orbispeek"
            && components.percentEncodedHost?.lowercased() == "image-access"
            && components.user == nil && components.password == nil && components.port == nil
            && components.percentEncodedPath.isEmpty
            && components.query == nil && components.fragment == nil
    }
}
