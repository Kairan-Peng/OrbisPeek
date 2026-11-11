import XCTest
@testable import QuicklookCore

final class PreviewVerificationTests: XCTestCase {
    private let installedExtension = URL(fileURLWithPath: "/Applications/Quicklook.app/Contents/PlugIns/QuicklookPreview.appex")
    private let version = "0.1.1"
    private let build = "9"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var store: UserDefaults!
    private var suite: String!
    private var file: URL!

    override func setUpWithError() throws {
        suite = "org.quicklook.preview.tests.\(UUID().uuidString)"
        store = try XCTUnwrap(UserDefaults(suiteName: suite))
        file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("quicklook-sample.json")
    }

    override func tearDown() {
        store.removePersistentDomain(forName: suite)
        store = nil
    }

    func testMatchingTokenReconstructsReceiptWithLocalReceiveTime() throws {
        let request = try PreviewVerification.begin(fileURL: file, in: store, now: now)
        let token = try XCTUnwrap(token(for: request))
        XCTAssertEqual(token.count, 64)
        XCTAssertFalse(token.contains(request.id.uuidString))
        XCTAssertFalse(token.contains(request.filePath))
        XCTAssertEqual(token, self.token(for: request))
        let receivedAt = now.addingTimeInterval(2)
        let receipt = try XCTUnwrap(receipt(token, request: request, at: receivedAt))
        XCTAssertEqual(receipt.requestID, request.id)
        XCTAssertEqual(receipt.filePath, request.filePath)
        XCTAssertEqual(receipt.extensionIdentifier, ExtensionDiagnostics.extensionIdentifier)
        XCTAssertEqual(receipt.extensionPath, installedExtension.path)
        XCTAssertEqual(receipt.version, version)
        XCTAssertEqual(receipt.build, build)
        XCTAssertEqual(receipt.mode, "json")
        XCTAssertEqual(receipt.completedAt, receivedAt)
        XCTAssertNil(store.data(forKey: "Quicklook.samplePreview.receipt.v1"))
        XCTAssertNil(store.data(forKey: "Quicklook.samplePreview.observation.v1"))
    }

    func testWrongCopyVersionBuildAndTokenCannotConfirm() throws {
        let request = try PreviewVerification.begin(fileURL: file, in: store, now: now)
        let wrongCopy = try XCTUnwrap(token(for: request, extensionPath: "/tmp/Quicklook.app/Contents/PlugIns/QuicklookPreview.appex"))
        let wrongVersion = try XCTUnwrap(token(for: request, version: "0.1.0"))
        let wrongBuild = try XCTUnwrap(token(for: request, build: "8"))
        for token in [wrongCopy, wrongVersion, wrongBuild, "", "arbitrary-notification"] {
            XCTAssertNil(receipt(token, request: request))
        }
    }

    func testOldNonceOrPathCannotConfirmRetryAndOldCloseDoesNotCancelIt() throws {
        let first = try PreviewVerification.begin(fileURL: file, in: store, now: now)
        let oldToken = try XCTUnwrap(token(for: first))
        let next = try PreviewVerification.begin(fileURL: file, in: store, now: now)
        XCTAssertNil(receipt(oldToken, request: first))
        XCTAssertNil(receipt(oldToken, request: next))
        XCTAssertNil(token(for: first), "An old render must not borrow a retry's nonce")
        PreviewVerification.end(first, in: store)
        XCTAssertEqual(PreviewVerification.pendingRequest(for: file, in: store, now: now)?.id, next.id)
        let currentToken = try XCTUnwrap(token(for: next))
        XCTAssertNotNil(receipt(currentToken, request: next))

        let differentFile = file.deletingLastPathComponent().appendingPathComponent("other/quicklook-sample.json")
        let third = try PreviewVerification.begin(fileURL: differentFile, in: store, now: now)
        XCTAssertNil(receipt(currentToken, request: third))
        XCTAssertNil(PreviewVerification.pendingRequest(for: file, in: store, now: now))
        XCTAssertNil(PreviewVerification.renderedSampleToken(
            fileURL: file, mode: "json", request: third, in: store, now: now,
            identifier: ExtensionDiagnostics.extensionIdentifier, extensionPath: installedExtension.path,
            version: version, build: build
        ))
    }

    func testExpiredFutureAndCancelledRequestsCannotConfirm() throws {
        let request = try PreviewVerification.begin(fileURL: file, in: store, now: now)
        let token = try XCTUnwrap(token(for: request))
        XCTAssertNotNil(receipt(token, request: request, at: now.addingTimeInterval(120)))
        XCTAssertNil(receipt(token, request: request, at: now.addingTimeInterval(121)))
        XCTAssertNil(receipt(token, request: request, at: now.addingTimeInterval(-1)))
        XCTAssertNil(self.token(for: request, at: now.addingTimeInterval(121)))
        PreviewVerification.end(request, in: store)
        XCTAssertNil(receipt(token, request: request))
        XCTAssertNil(self.token(for: request))
    }

    func testOnlyBuiltInSamplesAndTheirExpectedModesCanProduceTokens() throws {
        XCTAssertThrowsError(try PreviewVerification.begin(
            fileURL: URL(fileURLWithPath: "/tmp/customer.json"), in: store, now: now
        ))
        XCTAssertThrowsError(try PreviewVerification.begin(
            fileURL: URL(string: "https://example.com/quicklook-sample.json")!, in: store, now: now
        ))
        let request = try PreviewVerification.begin(fileURL: file, in: store, now: now)
        XCTAssertNil(token(for: request, mode: "code"))
        XCTAssertNil(token(for: request, identifier: "another.provider"))
        for (name, mode) in [("quicklook-sample.md", "markdown"), ("quicklook-sample.jsonl", "jsonl"), ("quicklook-sample.toml", "code")] {
            let url = file.deletingLastPathComponent().appendingPathComponent(name)
            let request = try PreviewVerification.begin(fileURL: url, in: store, now: now)
            let token = try XCTUnwrap(PreviewVerification.renderedSampleToken(
                fileURL: url, mode: mode, request: request, in: store, now: now,
                identifier: ExtensionDiagnostics.extensionIdentifier, extensionPath: installedExtension.path,
                version: version, build: build
            ))
            XCTAssertEqual(receipt(token, request: request)?.mode, mode)
        }
    }

    func testCorruptOrOversizedRequestCannotConfirm() throws {
        let request = try PreviewVerification.begin(fileURL: file, in: store, now: now)
        let token = try XCTUnwrap(token(for: request))
        for data in [Data("invalid JSON".utf8), Data(repeating: 32, count: 16 * 1024 + 1)] {
            store.set(data, forKey: "Quicklook.samplePreview.request.v1")
            XCTAssertNil(PreviewVerification.pendingRequest(for: file, in: store, now: now))
            XCTAssertNil(receipt(token, request: request))
        }
    }

    func testDistributedNotificationObserverAcceptsOnceAndCanBeRemoved() throws {
        let request = try PreviewVerification.begin(fileURL: file, in: store, now: Date())
        let token = try XCTUnwrap(self.token(for: request, at: Date()))
        let received = expectation(description: "Receipt delivered through distributed notifications")
        received.assertForOverFulfill = true
        let observer = PreviewVerification.observeReceipt(
            for: request, expectedExtensionURL: installedExtension, version: version, build: build, in: store
        ) { receipt in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(receipt.requestID, request.id)
            received.fulfill()
        }
        defer { PreviewVerification.removeReceiptObserver(observer) }
        let center = DistributedNotificationCenter.default()
        for value in ["wrong-token", token, token] {
            center.postNotificationName(PreviewVerification.receiptNotificationName, object: value, userInfo: nil, deliverImmediately: true)
        }
        wait(for: [received], timeout: 3)

        let removed = expectation(description: "Removed observer remains silent")
        removed.isInverted = true
        let removedObserver = PreviewVerification.observeReceipt(
            for: request, expectedExtensionURL: installedExtension, version: version, build: build, in: store
        ) { _ in removed.fulfill() }
        PreviewVerification.removeReceiptObserver(removedObserver)
        center.postNotificationName(PreviewVerification.receiptNotificationName, object: token, userInfo: nil, deliverImmediately: true)
        wait(for: [removed], timeout: 0.15)
    }

    private func token(
        for request: PreviewVerification.Request, extensionPath: String? = nil,
        identifier: String = ExtensionDiagnostics.extensionIdentifier,
        version: String? = nil, build: String? = nil, mode: String = "json", at date: Date? = nil
    ) -> String? {
        PreviewVerification.renderedSampleToken(
            fileURL: file, mode: mode, request: request, in: store, now: date ?? now,
            identifier: identifier, extensionPath: extensionPath ?? installedExtension.path,
            version: version ?? self.version, build: build ?? self.build
        )
    }

    private func receipt(_ token: String, request: PreviewVerification.Request, at date: Date? = nil) -> PreviewVerification.Receipt? {
        PreviewVerification.receipt(
            matching: token, for: request, expectedExtensionURL: installedExtension,
            version: version, build: build, in: store, now: date ?? now
        )
    }
}
