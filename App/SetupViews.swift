import AppKit
import QuickLookUI
import QuicklookCore
import SwiftUI

struct SetupStatusCard: View {
    @ObservedObject var model: PreviewModel
    let showDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                if model.checkingPreview { ProgressView().controlSize(.small) }
                else {
                    Image(systemName: model.verificationSucceeded ? "checkmark.circle.fill" : "checkmark.shield")
                        .foregroundStyle(model.verificationSucceeded ? Color.green : Color.teal)
                }
                Text(model.verificationTitle).font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            Text(model.verificationDetail).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let snapshot = model.diagnostics {
                Label(snapshot.installation.title, systemImage: snapshot.installation == .applications ? "app.badge.checkmark" : "folder")
                    .font(.caption).foregroundStyle(.secondary)
                if !snapshot.extensionPresent {
                    Label("应用中的预览扩展缺失，请重新安装完整应用。", systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                } else if snapshot.querySucceeded, snapshot.registration == .ignored {
                    Label("Quicklook 目前已停用，请在系统设置中启用。", systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }
                if !snapshot.conflicts.isEmpty {
                    Text("可能影响预览的其他扩展：\(snapshot.conflicts.map(\.displayName).joined(separator: "、"))")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            HStack(spacing: 10) {
                Button("预览示例") { model.startSamplePreview() }
                    .buttonStyle(.borderedProminent).tint(.teal)
                Button("打开系统设置") { model.openSystemSettings() }
                Button("诊断详情", action: showDetails).buttonStyle(.link)
                Spacer(minLength: 0)
                Button {
                    Task { await model.refreshDiagnostics() }
                } label: { Image(systemName: "arrow.clockwise") }
                    .help("刷新安装与扩展信息").disabled(model.checkingDiagnostics)
            }.controlSize(.large)
        }
        .padding(20)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct SamplePreviewSheet: View {
    @ObservedObject var model: PreviewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("检查系统快速查看").font(.headline)
                Spacer()
                Picker("示例", selection: Binding(
                    get: { model.selectedSample }, set: { if let url = $0 { model.selectSample(url) } }
                )) {
                    ForEach(model.samples, id: \.self) { url in
                        Text(url.pathExtension.uppercased()).tag(Optional(url))
                    }
                }.frame(width: 180)
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(18)
            HStack(alignment: .top, spacing: 10) {
                if model.checkingPreview { ProgressView().controlSize(.small) }
                else { Image(systemName: model.verificationSucceeded ? "checkmark.circle.fill" : "info.circle").foregroundStyle(model.verificationSucceeded ? .green : .secondary) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.verificationTitle).font(.callout.bold())
                    Text(model.verificationDetail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                Button("重试") { if let url = model.selectedSample { model.selectSample(url) } }
            }.padding(.horizontal, 18).padding(.bottom, 14)
            DisclosureGroup("检查详情") {
                ScrollView {
                    Text(model.diagnosticReport()).font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 160)
            }.font(.caption).padding(.horizontal, 18).padding(.bottom, 10)
            Divider()
            if let url = model.selectedSample {
                SystemPreview(file: url).id(model.sampleRevision)
            }
            Divider()
            HStack {
                Text("此窗口使用系统快速查看。也可在 Finder 中选择自己的文档，按空格验证。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }.padding(14)
        }.frame(minWidth: 860, idealWidth: 960, minHeight: 640, idealHeight: 740)
    }
}

private struct SystemPreview: NSViewRepresentable {
    let file: URL
    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.shouldCloseWithWindow = false
        view.previewItem = file as NSURL
        return view
    }
    func updateNSView(_ nsView: QLPreviewView, context: Context) {}
    static func dismantleNSView(_ nsView: QLPreviewView, coordinator: ()) { nsView.close() }
}

struct DiagnosticsSheet: View {
    @ObservedObject var model: PreviewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("安装与扩展诊断").font(.title2.bold())
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            if let snapshot = model.diagnostics {
                Text(snapshot.installation.title + " · " + snapshot.registration.title).font(.headline)
                ForEach(snapshot.guidance, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary) }
            }
            ScrollView {
                Text(model.diagnosticReport()).font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(12).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("复制诊断报告") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.diagnosticReport(), forType: .string)
                }
                Button("刷新") { Task { await model.refreshDiagnostics() } }.disabled(model.checkingDiagnostics)
                Spacer()
                Button("打开系统设置") { model.openSystemSettings() }
            }
        }.padding(24).frame(width: 740, height: 610)
    }
}
