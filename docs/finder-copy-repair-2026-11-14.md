# Finder 复制修复与工具栏调整（1208）

已按用户要求修复并重新安装 `/Applications/OrbisPeek.app` 0.1.1（1208）。真实 Finder 渲染与原文选区 ⌘C、系统剪贴板和实际粘贴均通过；查找保持移除。预览内部不再可见地重复显示文件名，格式、编码、大小、行数和模式 / 换行图标保留。

## 原因与修复

1207 在 Finder 中拖选正文后复制，会由 Quick Look service 的 `copy:` 经 WebKit 命令分发再次返回 service，形成循环并耗尽栈。渲染和原文的两份独立崩溃报告均有相同的 32,635 层递归；原失败证据保留在 [复测记录](finder-copy-validation-2026-11-14.md)。

原代码只处理了快捷键和 supplemental action target，未覆盖该 service 的实际公共命令转发入口。本次在 `PreviewWebView.doCommand(by:)` 中接住正文 Copy，恰好向受控主文档分发一次，不再把该命令退回 WebKit 的 responder 链。加载中、关闭或未知请求停止复制旧 DOM；明确的原生编辑 / 输入法状态继续使用标准编辑行为。当前请求、视图代次和纯文本提取边界保留，没有私有 API、swizzle、全局监听或权限扩充。

有界回归模拟了同一路径：旧代码重入 service 8 次、正文复制 0 次；修复后 service 进入 1 次、正文复制 1 次。这比仅测试 `performKeyEquivalent` 更接近真实故障入口。另覆盖空选区、关闭 / 过期请求、输入控件复制 / 全选 / 粘贴和焦点竞态，降低同类回归风险。

## 工具栏

共享预览组件中的文件名 heading 改为非视觉辅助信息，保留文档 title 和无障碍文档身份。它不再占工具栏空间；文件名由外层 Quick Look / 阅读窗口标题展示。实际截图中，内部工具栏从格式信息开始，没有第二份可见文件名；原文模式同样成立。

## 自动检查与安装

- 93 项 JavaScript、62 项 Swift（41 Core + 21 UI）通过；覆盖报告器相关 35 项 Python 检查通过。
- 实际 WebKit 原生 Copy probe 的 19 项检查通过；渲染和原文复制的实际 pasteboard item 均只有 `public.utf8-plain-text`，同时验证空选区、编辑控件、过期请求和查找抑制。probe 完整恢复了原剪贴板。
- 独立只读审查通过；根代理合并冻结的 19 份应用源码 / 生成资源 hash 与签名构建一致。
- 新安装的完整 59 份文件与候选一致，主 / 扩展 deep/strict 签名、六份网页资源、195 项精确类型和唯一启用登记通过。宿主文档声明不变，七份原样例的默认打开应用在安装前、安装后及 UI 校验后完全一致。
- 1207 压缩备份位于 `~/Library/Application Support/OrbisPeek/Backups/20261114-101052/OrbisPeek-0.1.1-build1207.zip`，CRC 和两份二进制核对通过；旧 bundle 可从 `~/.Trash/OrbisPeek-0.1.1-build1207-20261114-101052.app` 恢复。

本次仍为原 Developer ID / App Group 的 Debug arm64 开发安装，不改默认关联、不重置全局缓存、不终止 Finder，不创建分支、提交或 PR。

## 真实 Finder 验收

使用新建合成文件，确认精确 `quicklook-app://bundle/index.html`、当前文档及新安装进程。通过截图坐标鼠标拖选，随后按 ⌘C；复制后正文、视图和扩展进程保持正常。

| 模式 | 选区与结果 |
|---|---|
| 渲染 | 跨普通文字、粗体和行内代码拖选；复制结果为 `渲染选区：中文加粗 与 inline_code。`，系统剪贴板显示“文本”，不包含 Markdown 标记或工具栏 |
| 原文 | 跨第 3–5 行拖选，选区实际跨过行号与空行；结果保留 `**中文加粗**`、反引号、空行及大整数，不夹带行号 4、5 |
| 实际粘贴 | 两个选区各粘贴到预先创建的普通 TextEdit 富文本文稿并保存；转换回文本后与独立预期逐字符一致，文稿没有粗体控制标记 |
| 稳定性 | 两种模式使用同一安装路径的扩展 PID 72485，复制前后均保持存活，没有出现原先扩展失败回退 |
| 界面 | 渲染和原文截图均只在外层标题显示文件名；内部显示元数据及两个图标，无查找或复制按钮 |

当前证据位于 `.build/validation/copy-repair-1208/`：`render/source-selection.png`、`render/source-after-copy.txt`、`render/source-clipboard.*`、`render/source-paste.txt`、已保存的两个 RTF、`paste-verification.json`、构建与安装检查。原生回归证据另保留在 `.build/validation/finder-copy-2026-11-14/native-copy-*`。

本轮实际 Finder 使用 Markdown 的渲染及原文视图，没有把识别范围中的所有格式写成重新验收。

自建 Finder 测试标签和两个已保存的 TextEdit 文稿已关闭，原 `README.zh-CN.md` 渲染预览已恢复；恢复后的截图也确认内部重复文件名消失。最终机器摘要为 `.build/validation/copy-repair-1208/acceptance-summary.json`，包含源码、完整安装、七份默认应用、同一存活进程和验收证据的 hash；未修改用户文稿。
