import Foundation

/// Bounded, request-scoped data only. It neither parses nor trusts document markup.
struct HTMLPreviewDocument {
    static let shellURL = URL(string: "quicklook-app://bundle/index.html")!
    static let maximumHTMLBytes = 2 * 1024 * 1024
    static let contentSecurityPolicy = "default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src quicklook-resource:; connect-src 'none'; font-src 'none'; media-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"

    struct Prepared {
        let url: URL
        let data: Data
    }

    struct ImageResource {
        let token: UUID
        let documentURL: URL
        let relativePath: String
    }

    enum PreparationError: Error {
        case inactiveRequest
        case tooLarge
    }

    private var requestID: UUID?
    private var documentURL: URL?
    private(set) var resourceToken: UUID?
    private var prepared: Prepared?

    @discardableResult
    mutating func beginRequest(_ requestID: UUID, documentURL: URL) -> UUID {
        invalidate()
        self.requestID = requestID
        self.documentURL = documentURL
        let token = UUID()
        resourceToken = token
        return token
    }

    mutating func invalidate() {
        requestID = nil
        documentURL = nil
        resourceToken = nil
        prepared = nil
    }

    mutating func discardPrepared(requestID: UUID) {
        guard self.requestID == requestID else { return }
        prepared = nil
    }

    mutating func prepare(_ html: String, requestID: UUID) throws -> Prepared {
        guard self.requestID == requestID else { throw PreparationError.inactiveRequest }
        prepared = nil
        guard html.utf8.count <= Self.maximumHTMLBytes else { throw PreparationError.tooLarge }
        let url = URL(string: "quicklook-app://bundle/document/\(UUID().uuidString)/content.html")!
        let result = Prepared(url: url, data: Data(html.utf8))
        prepared = result
        return result
    }

    func document(at url: URL) -> Prepared? {
        guard let prepared, url.absoluteString == prepared.url.absoluteString else { return nil }
        return prepared
    }

    func isCurrent(_ token: UUID) -> Bool { resourceToken == token }

    func imageResource(at url: URL) -> ImageResource? {
        guard url.absoluteString.utf8.count <= 16_384,
              let token = resourceToken, let documentURL,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "quicklook-resource", components.host == "local",
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil else { return nil }
        let prefix = "/\(token.uuidString)/"
        guard components.percentEncodedPath.hasPrefix(prefix) else { return nil }
        let encoded = String(components.percentEncodedPath.dropFirst(prefix.count))
        guard let path = encoded.removingPercentEncoding, !path.isEmpty, !path.hasPrefix("/"),
              !path.contains("\\"), !path.contains("\0"),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }) else { return nil }
        return ImageResource(token: token, documentURL: documentURL, relativePath: path)
    }

    static func bundleResource(at url: URL) -> String? {
        for name in ["index.html", "renderer.js", "styles.css"] {
            if url.absoluteString == "quicklook-app://bundle/\(name)" { return name }
        }
        return nil
    }
}
