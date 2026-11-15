# Finder 目录管理页直接唤起：公开接口补验

2026-11-14 在本机 macOS 27.0.1 / Apple Silicon 的真实 Finder 中补验。扩展内的直接唤起仍未成功；无效的 1215 / 1216 候选已撤回，源码和 `/Applications/OrbisPeek.app` 均恢复为此前验收的 0.1.1（1214）。未增加后台项、私有权限或用户目录授权。

## 问题与根因证据

复现条件是：Finder Space 打开含不可读本地图片的合成 Markdown，点击可信父页面中的“允许图片访问…”按钮。期望直接显示 OrbisPeek 的目录页，实际仍显示手动步骤。

图片提示和可信消息能正常到达原生端，目录页可手动打开，独立阅读器的固定 URI 入口此前已通过。此次失败边界在系统打开请求：`NSExtensionContext.open` 返回 `false`；Launch Services 路径返回 `NSCocoaErrorDomain 256`，同一时间的 CoreServicesUIAgent 日志指出调用扩展缺少 `com.apple.private.launchservices.allowedtolaunchinothersessions`。这不是继续扩大文件目录授权能解决的问题，也不据此断言其他 macOS 版本必然相同。

Apple 明确说明 [context.open 的支持由扩展点决定](https://developer.apple.com/documentation/foundation/nsextensioncontext/open(_:completionhandler:))。[NSWorkspace.openApplication](https://developer.apple.com/documentation/appkit/nsworkspace/openapplication(at:configuration:completionhandler:)) 是另一公开入口，但文档没有保证 Quick Look 可豁免启动限制，因而必须以真实 Finder 结果为准。

## 最小诊断矩阵

| 路径 | 状态 | 结果 |
|---|---|---|
| `context.open(orbispeek://image-access)` | 1214 与本轮真实 Finder | `false` |
| `NSWorkspace.open([URI], withApplicationAt: ownApp)` | 前轮 1211 | Cocoa 256，系统记录跨会话启动限制 |
| `NSWorkspace.openApplication(at: ownApp)`，不附 URI | 1215，宿主未运行 | Cocoa 256，目录页未启动 |
| 同上 | 1215，宿主已运行，PID 事先单独记录 | Cocoa 256，仍未进入目录页 |
| `context.open(ownAppFileURL)` | 1216，宿主未运行 | `false` |
| `NSWorkspace.open(ownAppFileURL, configuration:)` | 1216，宿主未运行 | Cocoa 256，目录页未启动 |

所有目标只由自身 bundle 推导，不接受文档提供的应用、目录或命令参数。异步 live DOM 检查及原生请求 / 视图代次检查保留；每次备用路径前重新验证当前状态。明确禁用运行副本替换。未把移除守卫或添加私有 entitlement 当作修复。

## 检查、撤回与防回归

- 1215 相关 6 项 Swift 检查与独立只读审查通过，两个签名候选均成功构建；这些不代替真实 Finder 的失败结果。
- 安装前保留 ZIP 与可恢复 bundle，每次安装核对 29 份运行时源码冻结、59 份文件、六份网页资源、195 个精确类型及唯一偏好插件。1216 首次登记尚无匹配，按相同安装路径重试后复验通过，未重置全局缓存。
- 诊断完成后，两份临时修改的源码逐字节恢复为 1214，全部 29 份冻结重新匹配；安装恢复为原 1214 的 59 份精确文件，签名和唯一登记复验通过。
- Finder 中重新预览真实 README，正文、模式工具栏和应用图标仍可见。自建测试标签已关闭，原项目和“资料”标签保留。未修改或清空真实目录授权，未运行系统剪贴板操作，查找保持移除。
- 临时手工启动 / 退出宿主准备热态时，旧预览请求曾失效并显示系统失败页；重新创建请求后再测试。没有将该失效页算成通过，也没有从现有证据推断为复制崩溃。

原始日志、冷 / 热态进程记录、候选冻结和恢复报告位于 `.build/validation/finder-host-launch-1215/` 与 `finder-host-launch-1216/`。主要文件为 `cold-open-results.log`、`cold-and-warm-open-results.log`、`launch-rejection.log`、`restore-1214.json`、`restored-installed-validation.json` 与 `restored-project-readme.txt`。

## 下一条可验证路线

用户随后明确选择“保持现状，不增加后台组件”。以下按需的、用户级 GUI 会话辅助进程仅作为未采用的研究方案记录：预览只发送固定的“打开目录页”请求，由该进程通过公开接口打开自身所属 App。只承载这一项操作，不传文档正文、文件路径或授权数据；不自动授予目录权限。目标是不常驻运行，空闲退出，并允许用户在系统后台项中停用。

该方案尚未验证成功，不能写成已解决。若未来重新采用，需先确认公开 ServiceManagement 注册、扩展到服务的受限通信、冷启动实际目录页、空闲退出、注销清理和失败回退。当前保留 1214 的手动回退与单页目录管理，不注册或启用辅助服务。

拟采用的最小方案与验收顺序：

1. 使用 [`SMAppService.agent(plistName:)`](https://developer.apple.com/documentation/servicemanagement/smappservice/agent(plistname:)) 管理 app 内同团队签名的用户级 LaunchAgent；只设一个 App Group 名下的 Mach 服务，`RunAtLoad=false`、`KeepAlive=false`，限定 Aqua GUI 会话，不启用管理员级 daemon。
2. 先由 Finder 发 UUID 做 ping / 同 UUID 回复，测到“原来未运行、点击才启动”。[App Groups 支持 Mach/XPC](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups)，双方使用公开签名要求限定准确身份；不扩大已有文件权限。
3. ping 通过后再尝试启动固定的 containing app，分别实测宿主未运行、主页关闭以及阅读器可见时，目录页确实显示；不能只依据 API 返回成功。
4. 无连接或未完成请求时，空闲约 30 秒后自行正常退出；再次点击可重新启动。[Apple 的按需生命周期说明](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html) 提醒避免启动不足 10 秒就退出，不能依靠 `KeepAlive=false` 自动退出。
5. [`register()`](https://developer.apple.com/documentation/servicemanagement/smappservice/register()) 后检查真实状态；需要用户批准时停在系统设置入口。验证停用与 [`unregister()`](https://developer.apple.com/documentation/servicemanagement/smappservice/unregister()) 后不能再次启动，目录授权保持原样。注册可用不等于进程常驻。

本次只进行上述文档 / SDK 研究，用户已拒绝该架构，未制作或启用后台服务。
