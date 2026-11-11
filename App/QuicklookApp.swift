import AppKit
import QuicklookCore
import QuicklookUI
import SwiftUI

@main
struct QuicklookApp: App {
    @StateObject private var model = PreviewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 780, minHeight: 560)
                .onOpenURL { model.open($0) }
        }
        .defaultSize(width: 1080, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开文件…") { model.chooseFile() }.keyboardShortcut("o")
            }
        }
    }
}

@MainActor
final class PreviewModel: ObservableObject {
    @Published var file: URL?
    @Published var revision = UUID()
    @Published var imageFolders: [String] = DirectoryAccess.grantedPaths()
    @Published var accessError: String?
    @Published var diagnostics: ExtensionDiagnosticsSnapshot?
    @Published var checkingDiagnostics = false
    @Published var showingSamplePreview = false
    @Published var samples: [URL] = []
    @Published var selectedSample: URL?
    @Published var sampleRevision = UUID()
    @Published var checkingPreview = false
    @Published var verificationSucceeded = false
    @Published var verificationTitle = "尚未验证预览"
    @Published var verificationDetail = "打开系统预览示例，确认 Quicklook 已正常工作。"
    @Published var sampleDiagnostics: [String: String] = [:]
    @Published private(set) var verifiedReceipt: PreviewVerification.Receipt?
    private var verificationTask: Task<Void, Never>?
    private var verificationRequest: PreviewVerification.Request?
    private var verificationObserver: NSObjectProtocol?

    func refreshDiagnostics() async {
        guard !checkingDiagnostics else { return }
        checkingDiagnostics = true
        diagnostics = await ExtensionDiagnostics.snapshot()
        checkingDiagnostics = false
    }

    func startSamplePreview() {
        do {
            samples = try OnboardingSamples.prepare()
            guard let sample = samples.first(where: { $0.pathExtension == "json" }) ?? samples.first else { return }
            selectSample(sample)
            showingSamplePreview = true
        } catch { accessError = "无法准备预览示例：\(error.localizedDescription)" }
    }

    func selectSample(_ url: URL) {
        finishSamplePreview()
        verificationSucceeded = false
        verifiedReceipt = nil
        let actualURL: URL
        do {
            // A fresh URL prevents Quick Look's cache from satisfying a new check.
            let fresh = try OnboardingSamples.prepare(freshForVerification: true)
            guard let sample = fresh.first(where: { $0.lastPathComponent == url.lastPathComponent }) else {
                throw CocoaError(.fileNoSuchFile)
            }
            samples = fresh
            actualURL = sample
        } catch {
            verificationTitle = "无法准备预览示例"
            verificationDetail = error.localizedDescription
            return
        }
        selectedSample = actualURL
        sampleRevision = UUID()
        guard PreviewVerification.isAvailable else {
            verificationTitle = "请检查示例预览"
            verificationDetail = "确认预览顶部显示 Quicklook 的格式、编码与查找工具栏。此开发构建未配置自动回执。"
            return
        }
        do {
            let request = try PreviewVerification.begin(fileURL: actualURL)
            verificationRequest = request
            let expectedExtension = Bundle.main.bundleURL.appendingPathComponent("Contents/PlugIns/QuicklookPreview.appex")
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
            verificationObserver = PreviewVerification.observeReceipt(
                for: request, expectedExtensionURL: expectedExtension, version: version, build: build
            ) { [weak self] receipt in
                Task { @MainActor in
                    guard let self, self.verificationRequest?.id == request.id else { return }
                    self.verificationTask?.cancel()
                    self.checkingPreview = false
                    self.verifiedReceipt = receipt
                    self.verificationSucceeded = true
                    self.verificationTitle = "Quicklook 已完成示例预览"
                    self.verificationDetail = "已收到扩展回执：\(actualURL.pathExtension.uppercased()) · \(receipt.version)（\(receipt.build)）"
                    self.sampleDiagnostics = PreviewVerification.diagnosticSummary()
                }
            }
            sampleDiagnostics = PreviewVerification.diagnosticSummary()
            checkingPreview = true
            verificationTitle = "正在验证系统预览…"
            verificationDetail = "等待 Quicklook 扩展完成示例预览。"
            verificationTask = Task { [weak self] in
                for _ in 0..<60 {
                    guard !Task.isCancelled, let self, self.verificationRequest?.id == request.id else { return }
                    self.sampleDiagnostics = PreviewVerification.diagnosticSummary()
                    do { try await Task.sleep(nanoseconds: 250_000_000) }
                    catch { return }
                }
                guard !Task.isCancelled, let self, self.verificationRequest?.id == request.id,
                      !self.verificationSucceeded else { return }
                self.checkingPreview = false
                self.verificationTitle = "尚未收到 Quicklook 的预览回执"
                self.verificationDetail = "暂时无法自动确认。请检查预览中的 Quicklook 工具栏，或在系统设置中确认扩展后重试。"
            }
        } catch {
            checkingPreview = false
            verificationTitle = "自动验证暂不可用"
            verificationDetail = "可先检查示例是否显示 Quicklook 工具栏，再查看诊断详情。\(error.localizedDescription)"
        }
    }

    func finishSamplePreview() {
        if checkingPreview {
            verificationTitle = "验证尚未完成"
            verificationDetail = "示例预览已关闭，可重新打开后继续检查。"
        }
        verificationTask?.cancel()
        verificationTask = nil
        if let observer = verificationObserver { PreviewVerification.removeReceiptObserver(observer) }
        verificationObserver = nil
        if let request = verificationRequest { PreviewVerification.end(request) }
        sampleDiagnostics = PreviewVerification.diagnosticSummary()
        verificationRequest = nil
        checkingPreview = false
    }

    func openSystemSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
    }

    func diagnosticReport() -> String {
        guard let diagnostics else { return "诊断正在准备。" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        var sampleReport = sampleDiagnostics
        if let receipt = verifiedReceipt {
            sampleReport["receiptID"] = receipt.requestID.uuidString
            sampleReport["receiptVersion"] = receipt.version + " (" + receipt.build + ")"
            sampleReport["receiptMode"] = receipt.mode
            sampleReport["receiptExtensionPath"] = receipt.extensionPath
            sampleReport["receiptReceivedAt"] = ISO8601DateFormatter().string(from: receipt.completedAt)
        }
        guard let encoded = try? encoder.encode(diagnostics),
              let object = try? JSONSerialization.jsonObject(with: encoded),
              let report = try? JSONSerialization.data(withJSONObject: [
                "extension": object, "samplePreview": sampleReport,
              ], options: [.prettyPrinted, .sortedKeys]) else { return "无法生成诊断报告。" }
        return String(data: report, encoding: .utf8) ?? "无法生成诊断报告。"
    }
    func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "选择要预览的文档"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }
    func open(_ url: URL) { file = url; revision = UUID() }

    func chooseImageFolder() {
        let panel = NSOpenPanel()
        panel.title = "允许本地图片访问"
        panel.message = "选择包含文档与图片的文件夹。Quicklook 仅在预览时读取本地图片；可随时撤销。"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = file?.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DirectoryAccess.grant(folderURL: url)
            imageFolders = DirectoryAccess.grantedPaths()
            revision = UUID()
        } catch { accessError = error.localizedDescription }
    }

    func revokeImageFolders() {
        do {
            try DirectoryAccess.revokeAll()
            imageFolders = DirectoryAccess.grantedPaths()
            revision = UUID()
        } catch { accessError = error.localizedDescription }
    }
}

private struct ContentView: View {
    @ObservedObject var model: PreviewModel
    @State private var showingImageAccess = false
    @State private var showingDiagnostics = false
    private let groups: [(String, String, String)] = [
        ("text.document", "Markdown", "排版、表格与代码块"),
        ("curlybraces", "JSON / JSONL", "格式化与逐行查看"),
        ("slider.horizontal.3", "配置文件", "YAML · TOML · INI"),
        ("chevron.left.forwardslash.chevron.right", "源码与日志", "高亮、换行与行号"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 25, weight: .medium)).foregroundStyle(.teal)
                    Text("Quicklook").font(.system(size: 21, weight: .semibold, design: .rounded))
                }.padding(.top, 10)
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(groups, id: \.1) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.0).font(.system(size: 16)).frame(width: 22).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.1).font(.system(size: 13, weight: .medium))
                                Text(item.2).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Spacer()
                Button {
                    model.file = nil
                    Task { await model.refreshDiagnostics() }
                } label: {
                    Label("安装与自检", systemImage: "checkmark.shield").frame(maxWidth: .infinity)
                }
                Text("\(FileTypeRegistry.supportedExtensions.count) 种后缀可识别")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                if DirectoryAccess.isAvailable {
                    Button { showingImageAccess = true } label: {
                        Label("本地图片访问", systemImage: "photo").frame(maxWidth: .infinity)
                    }
                }
                Button { model.chooseFile() } label: {
                    Label("打开文件…", systemImage: "folder").frame(maxWidth: .infinity)
                }.controlSize(.large)
                Text("本地处理 · 开源")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            .padding(24).frame(width: 235).frame(maxHeight: .infinity)
            .background(.quaternary.opacity(0.35))
            Divider()
            if let file = model.file {
                NativePreview(file: file).id(model.revision)
            } else {
                ScrollView { welcome.frame(maxWidth: 780, alignment: .leading) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await model.refreshDiagnostics() }
        .sheet(isPresented: $model.showingSamplePreview, onDismiss: model.finishSamplePreview) {
            SamplePreviewSheet(model: model)
        }
        .sheet(isPresented: $showingDiagnostics) {
            DiagnosticsSheet(model: model)
        }
        .sheet(isPresented: $showingImageAccess) {
            VStack(alignment: .leading, spacing: 18) {
                Text("本地图片访问").font(.title2.bold())
                Text("允许包含文档和图片的文件夹后，重新打开 Space 预览。图片仍限定在文档所在目录内，预览不加载网络图片。")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if model.imageFolders.isEmpty {
                    Text("尚未允许任何文件夹。选择文件夹后，请至少预览一次其中的 Markdown，让扩展保存授权。")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(model.imageFolders, id: \.self) { path in
                        Label(path, systemImage: "folder").font(.callout).textSelection(.enabled)
                    }
                }
                HStack {
                    Button("允许一个文件夹…") { model.chooseImageFolder() }.buttonStyle(.borderedProminent)
                    if !model.imageFolders.isEmpty {
                        Button("撤销全部") { model.revokeImageFolders() }
                    }
                    Spacer()
                    Button("完成") { showingImageAccess = false }.keyboardShortcut(.defaultAction)
                }
                Text("撤销后，关闭并重新打开已有预览即可生效。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(28).frame(width: 560)
        }
        .alert("操作未完成", isPresented: Binding(
            get: { model.accessError != nil }, set: { if !$0 { model.accessError = nil } }
        )) {
            Button("好") { model.accessError = nil }
        } message: { Text(model.accessError ?? "") }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("让文档，一眼可读。")
                .font(.system(size: 33, weight: .semibold, design: .rounded))
            Text("在 Finder 中选中文件，按下空格。\nMarkdown、数据、配置和代码，都有清晰的阅读方式。")
                .font(.system(size: 15)).foregroundStyle(.secondary).lineSpacing(6)
            HStack(spacing: 9) {
                ForEach([".md", ".jsonl", ".yaml", ".toml", ".swift"], id: \.self) { ext in
                    Text(ext).font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                }
            }
            SetupStatusCard(model: model, showDetails: { showingDiagnostics = true })
            Text("系统设置 → 通用 → 登录项与扩展 → 快速查看")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
            Text("TXT、HTML、PDF 和 Office 文档继续使用系统预览。")
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 8)
        }.padding(48)
    }
}

private struct NativePreview: NSViewControllerRepresentable {
    let file: URL
    func makeNSViewController(context: Context) -> PreviewWebController {
        let controller = PreviewWebController()
        Task { try? await controller.showFile(file) }
        return controller
    }
    func updateNSViewController(_ nsViewController: PreviewWebController, context: Context) {}
}
