# Markdown 本地图片：目录授权与跨进程验证

日期：2026-11-10。环境：macOS 27.0.1、Xcode 27.2、Apple Silicon。本轮没有更改钥匙串权限、创建证书、公证或发布，也没有读取用户的私有文档。所有隔离样本和可执行文件都在 `.build/bookmark-experiment/`。

## 结论

真实 Quick Look extension 只获得 Markdown 文件本身的读取权限，不能据此读取它引用的兄弟图片。宿主或非沙盒 probe 能显示图片，只证明渲染链正常，不能证明 extension 权限正常。

推荐使用用户明确选择的目录授权，避免 `/` 全盘 temporary exception：

1. 用户在宿主的 `NSOpenPanel` 中选择一个文档目录。
2. 宿主保留自己创建的显式只读目录 bookmark，用于自身后续启动与刷新。
3. 宿主把一个 `options: []` 的隐式目录 bookmark 作为权限交接写入 App Group。
4. extension 首次消费交接时取得目录 scope，随即在 extension **自己的进程中**创建显式只读 bookmark，保存到它自己的偏好设置。
5. 后续 extension 启动使用自己创建的显式 bookmark，无需宿主常驻。

不能只把宿主的显式 app-scoped bookmark 复制给 extension。本机隔离实验中，即使两者使用同一 Developer ID 证书，不同签名 identifier 的接收端也无法解析该显式 bookmark；隐式交接后由接收端自行转存的方案通过了新进程验证。

## 隔离实验与证据

实验使用一个非沙盒 Creator CLI 和独立 sandbox Consumer.app。二者使用本机同一 Developer ID 证书签名，签名 identifier 分别为 `org.quicklook.experiment.creator` 与 `org.quicklook.experiment.consumer`。Consumer 只配置 sandbox 和 app-scoped bookmark entitlement；它没有目录 temporary exception 或 App Group。

目标是本轮生成的 48 字节文件，名字为 `fixture/local-image.png`。该文件只用于证明读取权限，内容不是有效 PNG；真实图片显示需要在主 extension 中另验。预期 SHA-256 为 `67d57ab6067c1aa6c60f7e4262a690ee8f1884324bb1d0c3749c45683e933487`。

每个接收进程都在消费 bookmark 前尝试读取同一目标，确保结果不是来自原本已有的目录权限。

| 条件 | 结果 | 本地证据 |
|---|---|---|
| sandbox Consumer 基线，无 bookmark | 读取被拒绝：NSCocoaErrorDomain 257，底层 EPERM 1 | `explicit-result.json` / `implicit-result.json` 的 baseline |
| Creator 创建的显式目录 bookmark → 不同 identifier Consumer | 解析失败：NSCocoaErrorDomain 259，incorrect format | `explicit-result.json` |
| Creator 创建的隐式目录 bookmark → 不同 identifier Consumer | start=true，读取 48 字节，hash 一致；stop 后重新拒绝 | `implicit-result.json` |
| Consumer 消费隐式 bookmark 后自行创建显式 bookmark → 全新 Consumer 进程 | 新进程基线拒绝；显式解析 stale=false、start=true、读取成功；stop 后拒绝 | `rebound-fresh-result.json` |
| Creator 自己重新解析原显式 bookmark | 成功，说明原 bookmark 并非创建时已损坏 | `creator-own-explicit-result.json` |
| 对照 Consumer 改成与 Creator 相同签名 identifier，其他条件一致 | 原显式 bookmark 可以解析；基线仍拒绝、start 后可读 | `same-identifier-consumer-result.json` |
| document-scoped 单文件 bookmark，相对一个已获权限的 Markdown | 不同 identifier 的接收端成功读取目标单文件 | `documentImage-result.json` |
| document-scoped **目录** bookmark，相对 Markdown | 创建即被系统拒绝：NSCocoaErrorDomain 256，Item URL disallowed by security policy | `document-bookmarks.json` 的 documentFolderError |

这些证据位于 `.build/bookmark-experiment/`，不会作为产品资源分发。Creator 在 Consumer 执行前已退出；持久化对照也终止了旧 Consumer 后才启动新进程。

**尚未实测整机重启。**隐式 bookmark 不可作为长期授权；Apple 明确说明其临时 scope 最迟在重启时失效。Consumer 自建显式 bookmark 的跨启动行为已经验证，跨重启仍须补一项真实测试。macOS 15 / 26 尚无本轮对应运行证据。

## 已实现的 DirectoryAccess 边界

实现入口：`Sources/QuicklookCore/DirectoryAccess.swift`。

- 只有 `Bundle.main` 中非空的 `QuicklookAppGroup` 配置才启用目录授权；默认无 group 构建返回不可用。`isAvailable` 只检查配置，不主动请求 group 访问。
- group 中的 `directory-grants-v1.json` 原子写入当前授权，最多 32 个目录、2 MiB，单个 bookmark 不超过 32 KiB。
- 当前授权包含随机 UUID、规范目录路径和隐式 bookmark；宿主显式 bookmark 和 extension 显式 bookmark分别留在各自 `UserDefaults.standard`，不跨进程共用。
- extension 在读取私有 bookmark 缓存前必须先确认共享列表中仍存在对应 UUID 与目录路径；授权列表缺失或无效时失败关闭。
- 目录路径进行标准化、符号链接解析和带分隔符的后代匹配，避免 `/docs` 匹配 `/docs-other`。解析后的 bookmark 目录还必须与记录的目录一致。
- 只激活包含当前文档的已选目录；不会为寻找图片遍历未选择的目录。
- scope 对象必须一直保留到图片读取结束，析构时平衡 `stopAccessingSecurityScopedResource()`。
- 撤销原子清空共享授权并清理当前进程缓存；其他进程残留的私有缓存因 UUID 已不在共享列表中而不能用于新预览。**已经打开的预览持有的 scope 会在其生命周期结束时释放**，并非系统级即时吊销。
- 宿主调用 `grantedPaths()` 时，可用它自己保存的显式 bookmark 刷新隐式交接。这样用户重开宿主后，可以更新尚未被 extension 转存或已经过期的交接数据。宿主不需要常驻。

该机制仅扩展读取权限；图片路径仍需通过 `LocalResourcePolicy` 的目录内、光栅格式、大小和符号链接检查，文档的远程资源与脚本策略保持独立。

## App Group 的独立前提

跨进程 bookmark 实验没有使用 App Group，因此没有证明任意开发签名构建都能静默使用共享容器。Apple 当前文档列出了 group 访问条件：应用属于相同 group，使用正确 entitlement 与 `containerURL(forSecurityApplicationGroupIdentifier:)`，并满足 App Store / 公证以及 profile 或 Team ID 前缀等要求。不满足条件的开发构建可能触发系统授权或无法访问。[Apple 文件访问文档](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)

因此产品应保留普通构建的文本预览，目录授权作为正确配置的可选签名构建能力。不能把 group 路径字符串或成功创建 JSON 文件当作 extension 已获得外部目录权限的证据。

## 最小的真实 extension 验收

本机主集成已经完成下面第 1–5 项：未授权受限、宿主通过原生选择器允许 `samples/fixtures`、真实 Finder 扩展显示棋盘 PNG、退出宿主并重启扩展仍显示，以及撤销并重启后重新受限。远程图片在整个过程中仍被阻止。测试结束已撤销测试目录授权，未选择用户文档或根目录。第 6 项中的整机重启和其他系统版本尚未验证。

1. 未授权时打开 `samples/fixtures/markdown-local-images.md`，确认文本可读、本地图片明确受限。
2. 由用户在宿主选择 `samples/fixtures`，宿主记录当前授权；不选择用户文档目录或根目录作为开发测试样本。
3. 在 Finder 使用 Space 打开同一 Markdown，确认 extension 实际消费交接并显示生成的棋盘 PNG。
4. 退出宿主、终止当前 extension，再次 Space 打开，确认读取来自 extension 自己保存的显式 bookmark。
5. 撤销授权，关闭已有预览后重新打开，应重新受限；不能仅因为残留的私有缓存就继续读取。
6. 补做重启、目录被重命名／移动、缓存损坏、超过授权数量、符号链接越界等测试。目录移动后当前实现保守拒绝路径不一致的 bookmark，需要用户重新选择目录。

## 原始来源

- [Apple：Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)：用户选目录的递归访问、显式持久 bookmark、跨进程隐式 bookmark、App Group 条件。
- [Apple：NSURL bookmarkData](https://developer.apple.com/documentation/foundation/nsurl/bookmarkdata(options:includingresourcevaluesforkeys:relativeto:))：app-scoped 与 document-scoped 的身份和文档访问约束。
- [Apple：withoutImplicitSecurityScope](https://developer.apple.com/documentation/foundation/nsurl/bookmarkcreationoptions/withoutimplicitsecurityscope)：普通 bookmark 默认携带临时隐式 scope，其寿命最迟到重启。
- [Apple DTS：On File System Permissions](https://developer.apple.com/forums/thread/678819)：动态 sandbox extension、跨进程隐式 bookmark、目录层级和 MAC 边界。
- [Apple TN2312](https://developer.apple.com/library/archive/technotes/tn2312/_index.html)：document-scoped bookmark 的单文件、非目录限制；本机实验也验证了目录创建失败。
- [Apple TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)：签名证书身份、签名 identifier 和 designated requirement 的区别。书签跨 identifier 的具体行为以本轮隔离运行结果为准，未通过改写生产 app／extension identifier 规避限制。
- 本机 SDK：`Foundation.framework/Headers/NSURL.h`，关于显式 / 隐式 bookmark 和 scope 的 API 注释与上述公开文档一致。
