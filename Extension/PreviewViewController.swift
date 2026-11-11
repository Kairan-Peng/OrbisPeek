// Quick Look's extension entry point; rendering is shared with the diagnostic host.
import AppKit
import QuickLookUI
import QuicklookCore
import QuicklookUI

final class PreviewViewController: PreviewWebController, QLPreviewingController {
    func preparePreviewOfFile(at url: URL) async throws {
        let request = PreviewVerification.pendingRequest(for: url)
        onRender = { result in
            if case .success = result { PreviewVerification.observeRenderCompletion(fileURL: url, succeeded: true) }
            else { PreviewVerification.observeRenderCompletion(fileURL: url, succeeded: false) }
            guard case .success(let report) = result, let request,
                  let mode = report["mode"] as? String else { return }
            PreviewVerification.recordRenderedSample(fileURL: url, mode: mode, request: request)
        }
        try await showFile(url)
    }
}
