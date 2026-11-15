import AppKit
import QuicklookCore
import SwiftUI

@main
struct QuicklookApp: App {
    @StateObject private var model = PreviewModel()
    @NSApplicationDelegateAdaptor(DirectoryAccessOpenDelegate.self) private var applicationDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("OrbisPeek", id: "home") {
            SetupContentView(
                imageFolders: model.imageFolders,
                directoryAccessAvailable: DirectoryAccess.isAvailable,
                unclassifiedTextEnabled: model.unclassifiedTextEnabled,
                previewPreferencesAvailable: PreviewPreferences.isAvailable,
                chooseHomeFolder: model.chooseHomeImageFolder,
                chooseFolder: model.chooseImageFolder,
                removeFolder: model.removeImageFolder,
                setUnclassifiedTextEnabled: model.setUnclassifiedTextEnabled
            )
            .frame(minWidth: 500, minHeight: 540)
            .background(SetupWindowReference(model: model))
            .onAppear {
                model.presentSetupWindow = { openWindow(id: "home") }
                applicationDelegate.connect(model)
            }
            .alert("操作未完成", isPresented: Binding(
                get: { model.accessError != nil },
                set: { if !$0 { model.accessError = nil } }
            )) {
                Button("好") { model.accessError = nil }
            } message: { Text(model.accessError ?? "") }
        }
        .defaultSize(width: 600, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("目录权限…") { model.showSetup() }
            }
        }
    }
}

@MainActor
final class DirectoryAccessOpenDelegate: NSObject, NSApplicationDelegate {
    private weak var model: PreviewModel?
    private var pendingImageAccess = false

    func connect(_ model: PreviewModel) {
        self.model = model
        if pendingImageAccess {
            pendingImageAccess = false
            model.showSetup()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: ImageAccessRoute.matches) else { return }
        if let model { model.showSetup() }
        else { pendingImageAccess = true }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { model?.showSetup() }
        return true
    }
}

@MainActor
final class PreviewModel: ObservableObject {
    @Published var imageFolders: [String] = DirectoryAccess.grantedPaths()
    @Published var unclassifiedTextEnabled = PreviewPreferences.unclassifiedTextEnabled
    @Published var accessError: String?
    private var imageFolderPanel: NSOpenPanel?
    weak var setupWindow: NSWindow?
    var presentSetupWindow: (() -> Void)?

    func attachSetupWindow(_ window: NSWindow) {
        setupWindow = window
    }

    func showSetup() {
        imageFolders = DirectoryAccess.grantedPaths()
        unclassifiedTextEnabled = PreviewPreferences.unclassifiedTextEnabled
        presentSetupWindow?()
        if setupWindow?.isMiniaturized == true { setupWindow?.deminiaturize(nil) }
        setupWindow?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func chooseImageFolder() {
        let initialDirectory = imageFolders.first.map { URL(fileURLWithPath: $0, isDirectory: true) }
        requestImageFolderAccess(startingAt: initialDirectory, isHome: false)
    }

    func setUnclassifiedTextEnabled(_ enabled: Bool) {
        do {
            try PreviewPreferences.setUnclassifiedTextEnabled(enabled)
            unclassifiedTextEnabled = enabled
        } catch { accessError = error.localizedDescription }
    }

    func chooseHomeImageFolder() {
        // A sandbox's Foundation home can be its container. The account lookup
        // supplies only the picker's location; confirmation still grants access.
        guard let home = UserHomeDirectory.current() else {
            chooseImageFolder()
            return
        }
        requestImageFolderAccess(startingAt: home, isHome: true)
    }

    private func requestImageFolderAccess(startingAt directory: URL?, isHome: Bool) {
        guard imageFolderPanel == nil else { return }
        let panel = NSOpenPanel()
        panel.title = isHome ? "允许读取个人目录" : "选择其他目录"
        panel.message = isHome
            ? "确认后可读取个人目录中的文档及本地图片。仅允许只读访问，可随时移除。"
            : "选择包含文档和图片的目录。仅授予只读访问，可随时移除。"
        panel.prompt = "允许读取"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = directory
        imageFolderPanel = panel
        let complete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            self.imageFolderPanel = nil
            guard response == .OK, let url = panel.url else { return }
            do {
                try DirectoryAccess.grant(folderURL: url)
                self.imageFolders = DirectoryAccess.grantedPaths()
            } catch { self.accessError = error.localizedDescription }
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = setupWindow {
            panel.beginSheetModal(for: window, completionHandler: complete)
        } else {
            complete(panel.runModal())
        }
    }

    func removeImageFolder(_ path: String) {
        do {
            try DirectoryAccess.revoke(folderURL: URL(fileURLWithPath: path, isDirectory: true))
            imageFolders = DirectoryAccess.grantedPaths()
        } catch { accessError = error.localizedDescription }
    }
}

private struct SetupWindowReference: NSViewRepresentable {
    let model: PreviewModel
    func makeNSView(context: Context) -> NSView { WindowReferenceView(model: model) }
    func updateNSView(_ view: NSView, context: Context) {}
}

private final class WindowReferenceView: NSView {
    weak var model: PreviewModel?
    init(model: PreviewModel) { self.model = model; super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { model?.attachSetupWindow(window) }
    }
}
