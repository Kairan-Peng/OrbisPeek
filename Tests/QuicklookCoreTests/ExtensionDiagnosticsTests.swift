import Foundation
import XCTest
@testable import QuicklookCore

final class ExtensionDiagnosticsTests: XCTestCase {
    private func registryLine(_ tag: String = "", _ identifier: String = ExtensionDiagnostics.extensionIdentifier,
                              version: String = "0.1.0", path: String) -> String {
        "\(tag)    \(identifier)(\(version))\tA95ED493-9932-43EF-BDF6-5EB3E5CC2D43\t2026-09-15 12:39:42 +0000\t\(path)"
    }

    private func createBundle(at url: URL, types: [String]) throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["NSExtension": ["NSExtensionAttributes": ["QLSupportedContentTypes": types]]]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
    }

    func testParsesActualElectionMarkersAndPathsContainingSpaces() {
        let cases: [(String, ExtensionRegistrationState)] = [
            ("+", .preferred), ("-", .ignored), ("!", .debugger),
            ("=", .superseded), ("?", .unknown), ("", .defaultElection),
        ]
        let output = cases.enumerated().map { index, item in
            registryLine(item.0, "org.example.preview\(index)", path: "/Applications/My App.app/Contents/PlugIns/Preview Extension.appex")
        }.joined(separator: "\n") + "\n (6 plug-ins)\n"
        let result = ExtensionDiagnostics.parseRegistryOutput(output)
        XCTAssertTrue(result.isRecognized)
        XCTAssertEqual(result.entries.map(\.election), cases.map(\.1))
        XCTAssertEqual(result.entries.first?.appName, "My App")
        XCTAssertEqual(result.entries.first?.path, "/Applications/My App.app/Contents/PlugIns/Preview Extension.appex")
    }

    func testEmptyRegistryIsDifferentFromUnrecognizedOrRejectedOutput() {
        XCTAssertTrue(ExtensionDiagnostics.parseRegistryOutput(" (0 plug-ins)\n").isRecognized)
        XCTAssertFalse(ExtensionDiagnostics.parseRegistryOutput("").isRecognized)
        XCTAssertFalse(ExtensionDiagnostics.parseRegistryOutput("future row format\n (1 plug-in)\n").isRecognized)
        XCTAssertFalse(ExtensionDiagnostics.parseRegistryOutput("match: unauthorized discovery flag (PKDiscoverAll)\n").isRecognized)
        for result in [
            ExtensionDiagnostics.RegistryQueryResult(output: "match: unauthorized discovery flag (PKDiscoverAll)", exitCode: 1, error: nil),
            ExtensionDiagnostics.RegistryQueryResult(output: "unexpected future output", exitCode: 0, error: nil),
            ExtensionDiagnostics.RegistryQueryResult(output: "", exitCode: nil, error: "Permission denied"),
        ] {
            let snapshot = ExtensionDiagnostics.makeSnapshot(hostURL: URL(fileURLWithPath: "/Applications/Quicklook.app"), result: result)
            XCTAssertFalse(snapshot.querySucceeded)
            XCTAssertEqual(snapshot.registration, .unavailable)
            XCTAssertNotNil(snapshot.queryError)
            XCTAssertTrue(snapshot.ownRegistrations.isEmpty)
        }
    }

    func testQueryFailureDoesNotBecomeUnregisteredEvenWhenOutputHasRows() {
        let row = registryLine("+", path: "/Applications/Quicklook.app/Contents/PlugIns/QuicklookPreview.appex")
        let snapshot = ExtensionDiagnostics.makeSnapshot(
            hostURL: URL(fileURLWithPath: "/Applications/Quicklook.app"),
            result: .init(output: row, exitCode: 1, error: nil)
        )
        XCTAssertEqual(snapshot.registration, .unavailable)
        XCTAssertTrue(snapshot.conflicts.isEmpty)
    }

    func testOwnPhysicalCopyIsMatchedWithoutCollapsingDifferentVersions() {
        let host = URL(fileURLWithPath: "/Applications/Quicklook.app")
        let currentPath = host.appendingPathComponent("Contents/PlugIns/QuicklookPreview.appex").path
        let output = [
            registryLine("=", version: "0.0.9", path: "/Users/example/Downloads/Quicklook.app/Contents/PlugIns/QuicklookPreview.appex"),
            registryLine("+", version: "0.1.0", path: currentPath),
        ].joined(separator: "\n")
        let snapshot = ExtensionDiagnostics.makeSnapshot(hostURL: host, result: .init(output: output, exitCode: 0, error: nil))
        XCTAssertEqual(snapshot.registration, .preferred)
        XCTAssertEqual(snapshot.ownRegistrations.count, 2)
        XCTAssertTrue(snapshot.guidance.contains(where: { $0.contains("多份 Quicklook") }))
    }

    func testRegistrationOfAnotherCopyDoesNotClaimCurrentCopyIsEnabled() {
        let output = registryLine("+", path: "/Users/example/Downloads/Quicklook.app/Contents/PlugIns/QuicklookPreview.appex")
        let snapshot = ExtensionDiagnostics.makeSnapshot(
            hostURL: URL(fileURLWithPath: "/Applications/Quicklook.app"),
            result: .init(output: output, exitCode: 0, error: nil)
        )
        XCTAssertEqual(snapshot.registration, .differentCopy)
        XCTAssertTrue(snapshot.querySucceeded)
    }

    func testDefaultElectionIsNotPresentedAsEnabled() {
        let host = URL(fileURLWithPath: "/Applications/Quicklook.app")
        let output = registryLine(path: host.appendingPathComponent("Contents/PlugIns/QuicklookPreview.appex").path)
        let snapshot = ExtensionDiagnostics.makeSnapshot(hostURL: host, result: .init(output: output, exitCode: 0, error: nil))
        XCTAssertEqual(snapshot.registration, .defaultElection)
        XCTAssertEqual(snapshot.registration.title, "由系统选择")
        XCTAssertTrue(snapshot.guidance.contains(where: { $0.contains("不能证明 Finder") }))
    }

    func testConflictRequiresReadableExactTypeOverlapAndRelevantElection() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let host = base.appendingPathComponent("Quicklook.app")
        let own = host.appendingPathComponent("Contents/PlugIns/QuicklookPreview.appex")
        try createBundle(at: own, types: ["net.daringfireball.markdown"])
        var rows = [registryLine("+", path: own.path)]
        let candidates: [(String, String, String, [String])] = [
            ("Other Markdown", "org.example.markdown", "", ["net.daringfireball.markdown", "org.example.unrelated"]),
            ("Archive", "org.example.archive", "+", ["public.zip-archive"]),
            ("Ignored", "org.example.ignored", "-", ["net.daringfireball.markdown"]),
            ("Old", "org.example.old", "=", ["net.daringfireball.markdown"]),
            ("System", "com.apple.example", "+", ["net.daringfireball.markdown"]),
        ]
        for item in candidates {
            let url = base.appendingPathComponent(item.0 + ".app/Contents/PlugIns/Preview.appex")
            try createBundle(at: url, types: item.3)
            rows.append(registryLine(item.2, item.1, path: url.path))
        }
        rows.append(registryLine("+", "org.example.unreadable", path: base.appendingPathComponent("Missing.app/Contents/PlugIns/Preview.appex").path))
        let snapshot = ExtensionDiagnostics.makeSnapshot(hostURL: host, result: .init(output: rows.joined(separator: "\n"), exitCode: 0, error: nil))
        XCTAssertTrue(snapshot.extensionPresent)
        XCTAssertEqual(snapshot.conflicts.count, 1)
        XCTAssertEqual(snapshot.conflicts.first?.displayName, "Other Markdown")
        XCTAssertEqual(snapshot.conflicts.first?.overlappingTypes, ["net.daringfireball.markdown"])
        XCTAssertEqual(snapshot.unreadablePluginCount, 1)
    }

    func testInstallLocationAndUnregisteredEmptyQuery() {
        XCTAssertEqual(ExtensionDiagnostics.installationLocation(for: URL(fileURLWithPath: "/Applications/Quicklook.app")), .applications)
        XCTAssertEqual(ExtensionDiagnostics.installationLocation(for: URL(fileURLWithPath: "/Volumes/Quicklook/Quicklook.app")), .diskImage)
        XCTAssertEqual(ExtensionDiagnostics.installationLocation(for: URL(fileURLWithPath: "/Users/example/work/.build/xcode/Quicklook.app")), .development)
        let snapshot = ExtensionDiagnostics.makeSnapshot(hostURL: URL(fileURLWithPath: "/Applications/Missing.app"), result: .init(output: " (0 plug-ins)", exitCode: 0, error: nil))
        XCTAssertFalse(snapshot.extensionPresent)
        XCTAssertTrue(snapshot.querySucceeded)
        XCTAssertEqual(snapshot.registration, .unregistered)
    }
}
