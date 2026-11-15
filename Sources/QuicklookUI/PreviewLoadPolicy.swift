import QuicklookCore

public enum PreviewLoadPolicy: Sendable, Equatable {
    case standard
    case unclassifiedText

    var decodingPolicy: TextDecodingPolicy {
        self == .unclassifiedText ? .verifiedUnicode : .automatic
    }

    var forcePlainText: Bool { self == .unclassifiedText }
    var showsLoadFailure: Bool { self == .standard }
}
