import AppKit
import Foundation

/// Keeps each explicit reader independent of the setup window and other loads.
@MainActor
public final class ReaderWindowCoordinator {
    private var readers: [UUID: ReaderWindowController] = [:]

    public init() {}

    public func open(_ url: URL) throws {
        guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let access = ReaderDocumentAccess(url: url)
        let fileURL = access.url
        let id = UUID()
        let reader = ReaderWindowController(fileURL: fileURL, access: access) { [weak self] in
            self?.readers.removeValue(forKey: id)
        }
        readers[id] = reader
        reader.start()
        // This is the direct, explicit document/open action. Render callbacks
        // only act on an already-key reader; they never activate an application.
        reader.showWindow(nil)
        reader.window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class ReaderWindowController: NSWindowController, NSWindowDelegate {
    let preview = PreviewWebController()
    private let fileURL: URL
    private var access: ReaderDocumentAccess?
    private let onClose: () -> Void
    private(set) var loadTask: Task<Void, Never>?
    private var closed = false

    init(fileURL: URL, access: ReaderDocumentAccess?, onClose: @escaping () -> Void) {
        self.fileURL = fileURL
        self.access = access
        self.onClose = onClose
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = fileURL.lastPathComponent + " · OrbisPeek"
        window.minSize = NSSize(width: 480, height: 320)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = preview
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("OrbisPeekReader")
    }

    required init?(coder: NSCoder) { nil }

    func start() {
        guard !closed, loadTask == nil else { return }
        loadTask = Task { @MainActor [weak self] in
            guard let self, !closed, !Task.isCancelled else { return }
            do { try await preview.showFile(fileURL) }
            catch { /* The shared preview displays the current load error. */ }
            guard !closed else { return }
            loadTask = nil
        }
    }

    override func close() {
        finish()
        super.close()
    }

    func windowWillClose(_ notification: Notification) { finish() }

    private func finish() {
        guard !closed else { return }
        closed = true
        loadTask?.cancel()
        loadTask = nil
        preview.invalidatePreview()
        access = nil
        onClose()
    }
}
