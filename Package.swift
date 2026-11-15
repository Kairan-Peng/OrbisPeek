// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Quicklook",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "QuicklookCore", targets: ["QuicklookCore"]),
        .library(name: "QuicklookUI", targets: ["QuicklookUI"]),
        .executable(name: "quicklook-probe", targets: ["QuicklookProbe"]),
    ],
    targets: [
        .target(name: "QuicklookCore", resources: [.process("Resources")]),
        .target(name: "QuicklookUI", dependencies: ["QuicklookCore"], resources: [.process("Resources")]),
        .executableTarget(name: "QuicklookProbe", dependencies: ["QuicklookCore", "QuicklookUI"]),
        .testTarget(name: "QuicklookCoreTests", dependencies: ["QuicklookCore"]),
        .testTarget(name: "QuicklookUITests", dependencies: ["QuicklookUI"]),
    ],
    swiftLanguageModes: [.v5]
)
