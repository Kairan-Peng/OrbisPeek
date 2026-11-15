import Foundation

public enum PreviewRoutingDecision: Sendable, Equatable {
    case supportedType
    case unclassifiedText
    case system
}

public enum PreviewRoutingPolicy {
    public static let unclassifiedType = "public.data"

    public static func decision(for contentType: String?,
                                unclassifiedTextEnabled: Bool = false) -> PreviewRoutingDecision {
        guard let contentType else { return .system }
        if contentType == unclassifiedType { return unclassifiedTextEnabled ? .unclassifiedText : .system }
        if contentType == "public.html" || contentType == "public.xhtml" { return .system }
        return FileTypeRegistry.supportedUTIs.contains(contentType) ? .supportedType : .system
    }
}
