import AppKit
import SwiftUI

/// The empty directory state is also the first-use guide. Value inputs let
/// layout checks exercise it without changing a user's saved folder grants.
struct SetupContentView: View {
    let imageFolders: [String]
    let directoryAccessAvailable: Bool
    let unclassifiedTextEnabled: Bool
    let previewPreferencesAvailable: Bool
    let chooseHomeFolder: () -> Void
    let chooseFolder: () -> Void
    let removeFolder: (String) -> Void
    let setUnclassifiedTextEnabled: (Bool) -> Void
    var appIcon: NSImage = NSApplication.shared.applicationIconImage

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 9) {
                Image(nsImage: appIcon)
                    .resizable().interpolation(.high).scaledToFit()
                    .frame(width: 88, height: 88)
                    .accessibilityHidden(true)
                Text("OrbisPeek")
                    .font(.system(size: 29, weight: .semibold, design: .rounded))
                VStack(spacing: 5) {
                    Text("按下空格，看见更多。")
                        .font(.system(size: 19, weight: .medium, design: .rounded))
                    Text("Press Space. See more.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            directoryAccess
            textPreviewOption
        }
        .padding(28)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var directoryAccess: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("目录权限").font(.headline)
                Spacer()
                if directoryAccessAvailable && !imageFolders.isEmpty {
                    Menu {
                        Button("允许读取个人目录…", action: chooseHomeFolder)
                        Button("选择其他目录…", action: chooseFolder)
                    } label: { Image(systemName: "plus") }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("添加目录")
                    .accessibilityLabel("添加目录")
                }
            }
            if !directoryAccessAvailable {
                Text("此版本暂不支持本地图片目录授权。")
                    .font(.callout).foregroundStyle(.secondary)
            } else if imageFolders.isEmpty {
                Text("允许只读访问个人目录，让常用项目和笔记中的本地图片正常显示。")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Button("允许读取个人目录…", action: chooseHomeFolder)
                        .buttonStyle(.borderedProminent).tint(.teal)
                        .controlSize(.large)
                        .help("选择个人目录并确认只读访问")
                    Button("选择其他目录…", action: chooseFolder)
                        .buttonStyle(.link)
                }
                Text("可随时移除；也可稍后设置，文字预览无需授权。")
                    .font(.caption).foregroundStyle(.tertiary)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(imageFolders.enumerated()), id: \.element) { index, path in
                            if index > 0 { Divider().padding(.leading, 34) }
                            folderRow(path)
                        }
                    }
                }
                .frame(height: min(CGFloat(imageFolders.count) * 61, 122))
                Text("仅允许只读访问。添加或移除后，请重新打开预览。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }

    private var textPreviewOption: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("无后缀文本预览", isOn: Binding(
                get: { unclassifiedTextEnabled },
                set: setUnclassifiedTextEnabled
            ))
            .toggleStyle(.switch)
            .disabled(!previewPreferencesAvailable)
            .accessibilityIdentifier("unclassified-text-preview")
            Text(previewPreferencesAvailable
                 ? "仅尝试可读文本。更改后请重新打开预览。"
                 : "此版本暂不支持共享预览设置。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 6)
    }

    private func folderRow(_ path: String) -> some View {
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        return HStack(spacing: 12) {
            Image(systemName: "folder").foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(folder.lastPathComponent).font(.callout.weight(.medium))
                    .lineLimit(1).truncationMode(.middle)
                Text(path).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(path)
            Button { removeFolder(path) } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless).foregroundStyle(.secondary)
            .help("移除此目录的访问权限")
            .accessibilityLabel("移除目录：\(path)")
        }
        .padding(.vertical, 10)
    }
}
