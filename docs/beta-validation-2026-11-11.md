# 0.1.1 本地测试版验收记录

本轮完成安装自检、专用插件清理、无需系统重启的日常验收，以及签名 Release 的 ZIP / DMG 流水线。最终安装版本为 **0.1.1（10）**，路径为 `/Applications/Quicklook.app`，与最终 ZIP 中的应用文件树、可执行文件和签名检查结果完全一致。

测试环境是 macOS 27.0.1、Xcode 27.2、Apple Silicon。本轮没有重启、注销、关闭系统安全机制或提交 Apple 公证。用户明确暂缓公证，manifest 保持 `not-submitted`。

## 实际结果

| 项目 | 结果与证据 |
|---|---|
| 冲突插件清理 | QLMarkdown 1.0.15、Syntax Highlight 2.1.15、BetterZipQL 5.2 已从原路径移入废纸篓，并在移动前备份 ZIP；前两个 cask 的安装元数据已卸载。保留偏好、容器、Apple / Xcode / GarageBand 集成 |
| 首次标准路径安装与升级 | 首次放入 `/Applications` 后，完成同 bundle ID / 签名团队 / 路径的多个 build 升级。每次保留旧应用；安装校验没有必需项失败 |
| 系统样本自检 | build 9 的 JSON、JSONL、TOML、Markdown 均通过真实 `QLPreviewView` 和本次回执检查；JSON 保留大整数与重复键，JSONL 坏行之后仍显示中文记录；重试也产生有效的新回执 |
| Finder Space | 普通 workspace 文件夹的 Markdown 显示本项目工具栏、任务列表、表格和代码块；最终 ZIP 重装 build 10 后再次通过 |
| 图片授权 | 未授权时图片受限；只授权本轮样本目录后棋盘图片显示。关闭预览、退出宿主并终止本项目旧扩展进程后，新进程仍显示图片。旧 PID 87831，新 PID 88562，宿主未常驻 |
| 撤销 | 撤销本轮两个测试目录，关闭并重开 Finder 预览后图片重新受限，文字仍可读；最终没有保留本轮目录授权 |
| 卸载 | build 9 移到废纸篓，精确路径及所有本项目已登记的有效副本检查通过。TXT 中文 / emoji 和 HTML 排版仍可通过系统 Space 预览 |
| 从 ZIP 重装 | 从最终 ZIP 解包、验签并安装 build 10；标准路径、启用 election、两种架构与生产签名校验通过，只有一份本项目登记，无已识别冲突 |
| 重装后的自检 | build 10 的 JSON 实际渲染并收到回执 `28199348-2453-4BC6-ACA4-54476DAE08CD`；宿主接收时间 `2026-11-10T16:11:17Z`。关闭样本后状态和诊断中的回执版本 / 模式 / 路径 / 时间仍保留 |
| Release 包体 | Universal arm64 / x86_64、Developer ID、Hardened Runtime、App Sandbox、目录授权、许可证通过；无调试注入、`get-task-allow` 或全盘临时读取例外；ZIP 解包与 DMG 只读挂载检查通过 |
| 自动检查 | `scripts/test`：40 项 Swift、20 项 JavaScript 通过；安装检查器的 3 项 Python 测试通过 |

## 自检的实现边界

宿主的沙盒不允许直接读取完整 PlugInKit 登记，因此界面将该状态显示为不可读取，不能据此判断停用。终端只读诊断另确认最终只有 `/Applications` 下这一份登记，election 为 preferred，已识别冲突为 0。登记本身仍不能代替真实预览结果。

每次显式自检导出新 URL，并生成 120 秒有效的随机请求。扩展仅读取 App Group 请求；渲染成功后通过本地 distributed notification 发送由本次请求、实际扩展路径、ID、版本、build 和模式计算出的 SHA-256 校验值，不广播原始路径或 nonce。宿主只接受当前请求的预期值，关闭注销监听，重试换请求。通知可能丢失，因此超时保持未验证，不把通知当作安全认证。[实现与平台边界](extension-diagnostics.md)

本机实测 Quick Look worker 可读共享组文件，但不能创建共享回执文件或写共享偏好；没有通过扩展沙盒权限解决此限制。关闭样本会清除活动请求，因此诊断中请求不存在可以与已保留的成功回执同时出现。

内置缓存样本在嵌入式系统预览中正常，但相同缓存路径通过 Finder 预览曾转圈；相同内容复制到普通 workspace 目录后，Finder 正常选择本扩展。系统原因未确定。最终界面移除了直接揭示缓存样本到 Finder 的按钮，Finder 验收使用普通可访问目录中的文档。

## 交付与恢复

最终产物在 `dist/release/`：

- `Quicklook-0.1.1-macos-universal.zip`：1,443,388 字节。
- `Quicklook-0.1.1-macos-universal.dmg`：1,895,511 字节。
- 同名 `.manifest.json` 和 `.SHA256SUMS` 保存架构、版本、签名能力与完整性信息。

原有插件的恢复清单位于 `.build/plugin-removal/20261110T151130Z/removal.json`，ZIP 备份在同目录，废纸篓中也保留应用 / generator。没有清空废纸篓。需恢复时先在系统设置中停用本项目扩展，再将所需插件恢复原路径并重新登记；不要同时恢复全部竞争 provider。

本项目先前 build 的备份和卸载记录在 `.build/beta-validation/`。发布脚本和回退方法见 [发布说明](releasing.md)。这些本地恢复文件在忽略目录中，清理 `.build` 前应先决定是否仍需保留。

可复核的本地证据：

- `.build/beta-validation/fresh-install.json`、`upgraded-build6.json`：安装与升级检查。
- `.build/beta-validation/after-uninstall.json`、`uninstall-actions.json`：卸载与可恢复路径。
- `.build/beta-validation/reinstall-from-zip.json`、`reinstalled-build10.json`：最终 ZIP 重装。
- `.build/beta-validation/installed-final-app.json`：与最终 manifest 的 app 记录完全相等。
- `.build/beta-validation/final-diagnostics.json`：终端登记 / 冲突快照。
- `.build/beta-validation/ui-observations.json`：人工观察的 UI 验收记录，明确区分 build 9 的完整格式 / 权限流程和 build 10 的最终重装。
- `.build/beta-validation/final-tests.log`、`.build/release-package-build10.log`：自动检查与最终打包日志。

## 尚未验证

本轮使用既有开发账号，清除了已知专用竞争插件，不能称为全新用户账号或干净机器测试。未验证 macOS 15 / 26、Intel 实机、整机重启恢复和经过 Gatekeeper 的公证分发。Universal 编译与验签不代表这些运行环境已通过。

PDF / Office 继续使用系统能力，本轮没有新增 Office 渲染器或证明其完整排版保真。已有核心渲染与类型路由记录见 [首轮验证](validation-results.md)，不将 227 种可识别后缀自动视为全部 Finder 路由均已验收。
