# 安装与首次使用

[下载 OrbisPeek 0.1.1 Preview](https://github.com/Kairan-Peng/OrbisPeek/releases/tag/v0.1.1)（build 1227）：macOS 15+，Universal，包含 Apple Silicon `arm64` 与 Intel `x86_64`。这是早期预览版，使用 Developer ID 签名，**尚未提交 Apple 公证**。签名不等于 Apple 安全审核或 Gatekeeper 放行。

## 安装

在 Release 页的 **Assets** 中任选一种，两者包含同一个 App：

1. **DMG：** 打开 `OrbisPeek-0.1.1-macos-universal.dmg`，将 `OrbisPeek.app` 拖入 **Applications / 应用程序**，完成后推出磁盘映像。
2. **ZIP：** 解压 `OrbisPeek-0.1.1-macos-universal.zip`，将 `OrbisPeek.app` 移入 **应用程序**。

同页的 `.SHA256SUMS` 与 `.manifest.json` 用于核对完整性及构建信息；GitHub 自动生成的 **Source code** 压缩包是源码，不含可直接安装的 App。下载包已配置签名和共享容器，普通使用者不需要 Xcode、Node、开发者证书或自行配置 App Group。

升级时先退出旧 App、关闭 Quick Look 并保留旧版备份。使用 `/Applications` 中的安装，不要直接运行 DMG、下载目录或旧 `Quicklook.app` 中的重复副本。

从“应用程序”打开 **OrbisPeek** 一次。如果因未公证而被拦截，仅在确认下载来源可信、文件未遭篡改且接受预览版限制时，在首次尝试打开后前往 **系统设置 → 隐私与安全性 → 仍要打开**，按系统提示确认。该入口及 App / 扩展能否运行仍受系统版本和安全策略影响，不保证所有环境可放行。[Apple 官方说明](https://support.apple.com/zh-cn/102445)

若系统明确报告恶意软件、App 已损坏，或没有可用的单 App 确认入口，请停止安装并反馈；不需要关闭系统安全保护、删除隔离属性或修改全局安全策略。本预览版尚未完成真实互联网下载后的 Gatekeeper / 隔离首启全流程验收。

## 启用 Finder 预览

在 **系统设置 → 通用 → 登录项与扩展 → 快速查看** 中启用 **OrbisPeek Preview**，然后在 Finder 选中文件，按 **Space**。不同系统版本的设置名称可能略有不同；其他同类插件也会影响系统最终选择的预览提供器。

本 App 是预览插件，不改变默认打开应用。主页面仅有介绍、目录管理及可选设置，没有独立“打开文件… / ⌘O”或“打开方式 → OrbisPeek”入口。

## 一次确认只读目录授权

已支持格式的文字预览不要求目录授权。Markdown 引用的本地图片通常需要目录权限，因为 Quick Look 默认只把当前文档交给扩展。

- 首次打开 App 时，点 **允许读取个人目录…**。系统选择器默认定位你的用户主目录，由你确认一次只读授权；可取消。
- 只想开放一个项目或笔记库时，点 **选择其他目录…**，选择同时包含文档和图片的项目 / 笔记根目录。已有目录后，通过 **＋** 添加以上两类目录。
- 关闭已有 Quick Look，再回到 Finder 按 Space。扩展接收授权后，主 App 无需常驻。
- 撤销时点目录对应的 **−**，再关闭并重新打开预览。已打开的预览持有的访问范围会在其生命周期结束时释放，并非系统级即时吊销。

个人目录授权不绕过系统对私有应用数据的额外保护。图片仍须位于每份文档的目录或子目录，使用相对路径；不会因授权父目录而允许 `../`、绝对路径、符号链接越界、远程资源或 SVG。更名 / 移动目录后可能需要重新选择；失效时先重开 App，再重开预览。

图片不可读时会显示简短提示。在当前实测环境，Finder 无法直接唤起目录管理页；请按提示从“应用程序”手动打开 **OrbisPeek**，添加目录后重新预览。不需要后台辅助组件或完全磁盘访问。[权限机制与边界](local-image-access.md)

自行从源码构建时，默认 ad-hoc 构建保留文字预览，但没有共享目录能力。要启用目录授权和下面的共享开关，开发者需使用自己的 Developer ID 与 App Group，见 [构建说明](../README.zh-CN.md#构建)；下载包用户无需执行这些步骤。

## 可选的无后缀文本预览

App 主页的 **无后缀文本预览** 开关**默认关闭**。明确开启后，仅对实际类型直接为 `public.data` 的文件尝试文本预览；主要覆盖部分无后缀文件，不保证所有无后缀文件或 dotfile。更改后关闭并重新打开 Finder 预览，设置会保存，主 App 无需常驻。

此路径仅接受严格 UTF-8 或明确 BOM 的 UTF-16/32，不猜旧编码。读取阶段拒绝时恢复系统图标 / 文件信息，不保证自动调用其他提供器展示正文；异步 WebKit 错误仍可能显示本扩展错误页。任意陌生后缀通常是 `dyn.*` 类型，当前不提供统一接管。设置缺失或无效时保持关闭。

## 当前功能与限制

Markdown 默认渲染，可切换原文；JSON、JSONL、常见配置、日志和源码提供相应排版或高亮。工具栏显示类型、编码、大小与行数，适用格式有模式和换行图标。框选正文后按 **⌘C** 可复制纯文本，行号不随正文复制。当前没有查找功能。

**HTML / HTM / XHTML、TXT、PDF 和 Office 继续使用系统预览。** `.ts`、`.mts`、`.edn`、`.exs` 等可能与系统类型冲突；类型清单不等于全部后缀都能由本扩展显示正文。

每次读取最多 512 KiB + 4 字节，限制显示行数、长行高亮及图片资源；大文件显示前缀。本地图片仅受控光栅文件，不播放动画，不加载网络或 SVG；不执行文档自带脚本。旧编码推测有歧义，不承诺覆盖所有编码。

既有 Finder 功能实测主要来自 macOS 27.0.1 / Apple Silicon 的开发构建；历史 Debug 1226 结果不改记为 Release 1227 的完整运行验收。Universal 包含两种架构，但未完成 Intel 实机、其他系统版本及整机重启后的全面验证。完整范围见 [README](../README.zh-CN.md) 和 [功能清单](app-features-2026-11-14.md)。

## 卸载、回退与反馈

卸载前可在 App 中逐项移除目录授权，关闭预览、退出 App，再将“应用程序”中的 OrbisPeek 移到废纸篓。删除 App 默认保留设置缓存，不改写用户文档；临时停用可在系统设置中关闭本扩展。

回退时恢复之前保存的 App 至原安装位置，确认没有重复副本并重新启用，然后用一份合成样本按 Space 检查。无需全局重置文件关联或修改其他插件。

问题请到 [Issues](https://github.com/Kairan-Peng/OrbisPeek/issues) 提供版本 / 构建号、macOS、芯片类型、安装方式、步骤及可公开的最小合成样本。不要上传私人文档、原始授权数据或凭据；安全问题按 [SECURITY.md](../SECURITY.md) 私下报告。

## English quick start

Download the DMG or ZIP from [v0.1.1 Preview](https://github.com/Kairan-Peng/OrbisPeek/releases/tag/v0.1.1), move `OrbisPeek.app` to **Applications**, and open it once. It is Developer ID signed but **not notarized**. If you trust the download, follow [Apple's per-app approval instructions](https://support.apple.com/102445); availability depends on system policy. Enable **OrbisPeek Preview** under **System Settings → General → Login Items & Extensions → Quick Look**, then select a file in Finder and press Space.

In the app, confirm read-only access to your home folder or choose a project / notes folder for local Markdown images; use **−** to revoke. Close and reopen the preview after changing permissions or the default-off extensionless-text switch. The downloaded app is already configured; no developer account is needed. HTML stays with the system preview. Intel runtime, all supported macOS versions, reboot recovery and quarantined first launch are not fully verified.
