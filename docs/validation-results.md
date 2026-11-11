# 首轮实现与验证结果

日期：2026-11-10。环境：macOS 27.0.1（26A434）、Apple Silicon、Xcode 27.2（27B52）、Node 25.6.1。macOS 15 / 26 和 Intel 尚未实测。

## 复用与实现决定

采用小型共享外壳并选择性复用 FreeLook / QLStephenSwift 的 MIT 代码：有界读取、编码检测、类型映射、WKWebView 集成和 Markdown 任务列表处理。未完整 fork Glance，避免带入其旧 WebView、Go 构建链与无条件大文件拒绝；Markdown / 高亮 / JSON 使用社区模块而不是另写 parser。

来源与许可证见 `THIRD_PARTY_NOTICES.md`。运行时网页资源约 0.42 MB；首个 ad-hoc Debug 应用约 2.3 MB。后续构建、资源和签名会改变包体，这不是发布包尺寸承诺。

## 自动验证

| 层级 | 结果 | 权威证据 |
|---|---|---|
| Swift 核心 | 21 项测试通过 | `swift test`；`.build/swift-test.log` |
| JavaScript | 20 项测试通过 | `npm --prefix WebRenderer test` |
| 样本读取 | 60 个样本通过结构检查 | `.build/validation/fixture-inspect.json` |
| 实际 WKWebView | 19 场景、145 条断言、0 失败 | `.build/validation/core-results.json` |
| 宿主与扩展构建 | ad-hoc 基础构建和带 App Group 的 Developer ID 构建均成功；真实扩展已被 Finder 调用 | `.build/xcode/Build/Products/Debug/Quicklook.app`，下方人工实测 |
| 类型注册 | 227 后缀 / 86 格式组 / 56 文件名；191 个精确 UTI | `docs/file-types.md`、生成 plist 与构建产物 |
| 真实文件类型匹配 | 283 个后缀 / 文件名样本中，221 个精确匹配注册类型 | `.build/routing/after-build.json`；**这不等于 221 个已实际调用 provider** |

Swift 测试覆盖 BOM、无 BOM UTF-16、中文旧编码、截断边界、二进制、空文件及目录遍历 / 符号链接。Web 测试验证真实可见文字、JSON 大整数和重复键、JSONL 坏行续读、HTML / 脚本转义，以及本地资源边界。

100 MiB 日志与 1 GiB 稀疏 JSONL 每次只读取 **524,292 字节**。单次 WKWebView 首屏观察约 264 / 324 ms；没有进行统计基准、冷热启动分组或合计 WebContent 内存测量。1 GiB 样本只有前缀有效，不能据此宣称成功解析整份有效 1 GiB JSONL。

## Finder Space 人工验证

使用 Finder 选中文件并按 Space，观察实际 AX 内容与窗口。我们的视图具有 `quicklook-app://bundle/index.html` URL、格式 / 编码头与原文 / 换行 / 复制 / 查找控件，能与其他 provider 区分。

| 场景 | 实测 |
|---|---|
| `.jsonl` | 真实显示本项目 JSONL 视图与逐行记录 |
| `.json` | 真实显示格式化内容；`9007199254740993123456789` 和两个 `duplicate` 键均保留 |
| JSON 原文切换 / 查找 | 点击后显示原始单行；查找 `duplicate` 显示 `1 / 2` |
| Markdown | 暂时隔离 QLMarkdown 后，本项目视图正确显示 Markdown；未授权本地图片明确显示资源受限 |
| `.yaml` | 本项目视图显示注释、中文、锚点、块标量原文 |
| `.toml` | 本项目视图显示中文、注释、section、数组 |
| `.properties` | 本项目视图保留 `greeting=\u4F60\u597D` 原始转义 |
| `.ini` | 本项目视图显示 section、中文值和注释 |
| UTF-16 LE 日志 | 本项目视图显示 `UTF-16 LE` 与正确中文，没有被 NUL 检测误判为二进制 |
| Swift | 本项目源码视图显示 Swift 文件与 import 等内容 |
| HTML 保留系统 | 真实显示系统 HTML 预览，URL 为原始 `file://`，不是本项目的 `quicklook-app://` 视图 |
| TXT 保留系统 | 显示系统文本预览，没有本项目的网页和工具栏 |

这些是代表性样本，不是对所有后缀、所有文件内容或所有 macOS 的兼容性证明。

## 共存与图片边界

本机已装 QLMarkdown 与 Syntax Highlight。首次 Markdown 由 QLMarkdown 优先处理，不能算成本项目成功。验证时记录其 `pluginkit` election 后临时设为 `ignore`，仅隔离相关预览扩展；结束后恢复默认 election，不改用户的默认打开应用。

同一份 PNG 在普通 WKWebView 宿主里加载成功，在原始 Quick Look 沙盒中失败。由此证明权限问题真实存在，不能用宿主截图代替扩展验证。

隔离的书签实验进一步证明：不同 bundle identifier 即使使用同一 Developer ID，直接共享显式 app-scope bookmark 仍失败；通过隐式 bookmark 移交后，接收进程可以创建自己的显式 bookmark，并在新进程中恢复读取。转存前后都有“未授权读取失败 / 激活后成功 / 停止访问后失败”的对照。重启机器后的恢复尚未实测。

完整宿主 → App Group → 扩展流程已通过：

1. 在宿主的原生文件夹选择器里，只选择本项目生成的 `samples/fixtures`。
2. Finder Space 的本项目视图成功显示棋盘 PNG，同时仍阻止远程图片。
3. 退出宿主并终止当前扩展，再次启动新的扩展进程（PID 69079），图片仍显示；宿主进程当时未运行。
4. 重开宿主撤销授权，再次终止并启动扩展，本地图片重新显示不可读提示；残留的私有书签缓存未绕过撤销。
5. 结束时撤销了测试目录授权，并恢复了 QLMarkdown / Syntax Highlight 原来的默认 election。

签名集成时发现 Xcode Debug 默认注入 `get-task-allow` 导致系统拒绝 Developer ID 扩展；可选签名构建已设置 `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`。修正后真实扩展可正常启动，`codesign --verify --deep --strict` 通过。当前带目录授权的 Debug 应用约 3.0 MB，未公证或发布。

目录授权与书签机制详见 `docs/local-image-access.md`。完整流程已做进程重启验证，整机重启仍未实测。

## 尚未证明的范围

- macOS 15 / 26、Intel、干净机器及未安装其他 provider 的兼容性。
- 所有 227 后缀实际被 Finder 调用；`.ts/.mts` 等冲突和多数 dotfile 保留边界。
- 全部中文旧编码的自动识别，尤其极短且无 BOM 的歧义样本。
- Office 复杂版式与所有工作表 / 幻灯片；本项目保留系统 provider，但未做完整办公样本视觉验收。
- 公证、正式分发与升级流程；本轮只有本地开发签名，没有发布、提交或推送代码。
