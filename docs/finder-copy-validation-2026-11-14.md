# Finder 选区复制复测（2026-11-14）

结论：**1207 的 Finder 选区 ⌘C 在渲染、原文模式下均未通过。** 两种模式均能用鼠标拖出可见选区，但随后复制会导致预览扩展崩溃，不能标为正常的纯文本复制。

## 环境与操作

- 当前安装：`/Applications/OrbisPeek.app`，0.1.1（1207）。59 份安装文件与上次冻结候选一致，deep/strict 签名通过，PlugInKit 仅一份启用的本项目安装。
- 使用本轮新建的合成 Markdown，在 Finder 的真实 Quick Look 中观察精确 `quicklook-app://bundle/index.html`、文件名与正文；没有使用独立阅读窗口或离屏测试替代。
- 渲染态以截图坐标拖选一段跨普通文字、粗体和行内代码的正文；原文态另用全新文件请求，切换原文后拖选包含 Markdown 标记的对应行。截图均明确显示选区。
- 对每个选区执行 ⌘C，再检查预览状态和 Finder“显示剪贴板”。

| 模式 | 应复制的内容 | 实际结果 |
|---|---|---|
| 渲染 | `渲染选区：中文加粗 与 inline_code。` | 复制后自有正文消失，退回系统文件信息；首次剪贴板检查为空；扩展崩溃 |
| 原文 | ``渲染选区：**中文加粗** 与 `inline_code`。`` | 复制后显示“扩展在预览此文稿期间失败”；剪贴板仍为此前渲染段落，没有本次原文的星号 / 反引号；扩展崩溃 |

本轮还尝试过渲染态右键 Copy，后续剪贴板曾出现与渲染选区一致的“文本”。但该路径与菜单 Return / Finder 重命名焦点互相干扰，没有紧接操作的独立取样，因此不将右键复制计作可靠通过，也不将它计作失败。上述两次 ⌘C 崩溃则有独立、对应模式的直接证据。

## 崩溃证据

| 模式 | PID | 崩溃时间（UTC+8） | 结果 |
|---|---|---|---|
| 渲染 | 38739 | 09:45:26 | SIGSEGV，Stack Guard |
| 原文 | 63048 | 09:51:05 | SIGSEGV，Stack Guard |

两份报告的 84 个保留主线程帧完全一致，重复深度均为 32,635。循环涉及 `QLUIServiceBaseViewController copy:`、WebKit 命令分发和 `PreviewWebView.responds(to:)`。直接证据支持复制 responder 递归导致栈耗尽；不能据此把错误归为粘贴板写权限。保留栈中没有粘贴板写入函数，窄范围日志也未发现对应粘贴板拒绝。

原始与摘录证据位于 `.build/validation/finder-copy-2026-11-14/`，包括：

- `baseline.json`：安装身份、样例与期望文字。
- `render-selection.png`、`source-selection.png`：真实 Finder 选区。
- `source-after-copy.png`：系统明确显示扩展失败。
- `render-command-c-clipboard.*`、`source-command-c-clipboard.*`：系统剪贴板观察。
- `copy-crash-audit.md`、`source-copy-crash-audit.md`：独立只读崩溃审计及对应精简 JSON / 日志。

本次只校验并记录问题，没有修复代码、重建、重装、重置缓存或改动其他 provider。测试窗口已关闭，Finder 恢复到校验前的桌面状态。此前独立阅读窗口的复制验收结论保留，但不能替代 Finder 结果。

完整当前功能清单见 [App 功能清单](app-features-2026-11-14.md)。
