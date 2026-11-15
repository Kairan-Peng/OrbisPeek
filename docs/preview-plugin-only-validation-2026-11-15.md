# 预览插件入口收紧：1220 验收与未完成项

当前已安装 `/Applications/OrbisPeek.app` 0.1.1（1220）。两条独立文档打开入口已移除并实际验收；HTML 在 Finder 中使用本扩展工具栏的目标仍未实现。陌生后缀和无后缀文本尝试列为后续需求，没有在本轮扩大类型接管。

## 已完成的修改

- 从宿主 `project.yml` / `Config/App-Info.plist` 删除 HTML Viewer / Alternate 文档打开声明。
- 从 App 删除“打开文件…”、⌘O、file URL 阅读窗口分发、Reader 协调器接线及相应日志和隐藏主页状态。保留精确的 `orbispeek://image-access` 路由、冷启动待处理、再次打开 App 的主页恢复及原有目录选择 / 移除。
- 宿主只保留介绍与目录授权。共享 Reader 库、依赖及其开发测试暂留，产品无独立阅读入口。扩展的 HTML 精确声明与共享渲染实现保留；查找继续移除，无后台组件。
- 当前 README / 功能清单同步更新；历史独立阅读器验收保留为历史事实。

相对 1219 的 30 份运行时冻结，仅 App、宿主 plist、project.yml 三份改变。渲染器、复制、行号样式、权限 Core 及 195 项扩展声明保持。候选与安装共 59 份文件逐字节一致，六份网页资源与 1219 一致，deep / strict 签名通过。旧 1219 已压缩备份并保留可恢复 bundle。

## 验收结果

| 检查 | 结果与边界 |
|---|---|
| 声明回归 | 7/7 通过，包含实际临时目录 XcodeGen；要求宿主无文档 handler、保留精确权限 URL 路由 |
| 构建 / 安装 | Developer ID + App Group、Debug arm64，1220 构建成功；安装验证通过，唯一 preferred 插件在安装目录 |
| 文件菜单 | 实体菜单只有目录权限、系统关闭项；没有“打开文件…”或 ⌘O；在主页按 ⌘O 未出现文件选择器 |
| Finder 打开方式 | 合成 HTML 的实际完整菜单没有 OrbisPeek；默认仍为 Google Chrome |
| 目录主页 | 极简单页正常，原账号主目录项仍在；本轮没有新增或撤销授权 |
| Markdown | 真实 Finder 显示 `quicklook-app://bundle/index.html`；格式、编码、大小、行数可见，默认渲染、原文切换及换行 on → off 通过，无查找或复制按钮 |
| 默认打开应用 | 同七份既有合成样例的前后快照相同 |
| HTML / HTM / XHTML | 安装后以新文件路径分别复验，仍显示系统 `file://` HTML 内容；没有本扩展元数据 / 模式工具栏，**接管未通过** |
| 独立审查 | PASS，未发现入口移除或权限保留的阻塞问题 |
| 清理 | 关闭本轮合成预览及 `fixtures` 标签，恢复原 Finder 标签和文件选择；没有重启 Finder 或全局清缓存 |

首份 `.xhtml` 样本误用了 HTML 字节，系统显示 XML 错误；该观察单独保留，不作为有效内容验收。随后以 XML 解析器确认合法 XHTML，另存新路径 `installed-valid-1220.xhtml`，实体 Finder 正常显示正文但仍为系统提供器。HTML 标题中含有产品名只是合成文件自己的 `<title>`，不是本扩展身份；提供器判定依靠 URL、工具栏和实际内容。

本轮没有操作系统剪贴板或重新执行完整格式 / 复制实体验收；复制相关源码及资源哈希保持 1219，不能把不变性核对称为本轮 Finder 复制 / 粘贴重验。其他系统、Intel、公证分发和整机重启未验收。

## HTML 当前阻碍

目标界面已存在于共享渲染器：HTML 默认静态渲染，格式 / 编码 / 大小 / 行数、渲染与代码切换、换行按钮；渲染态禁用换行，原文态可使用。Finder 分发才是未完成的边界。

扩展已声明 `public.html`、`public.xhtml` 且唯一启用，1219 基线与 1220 新路径复验均进入系统 HTML。当前本机系统 Web 提供器也精确声明这些类型。本机 SDK 与 [Apple Quick Look UI 文档](https://developer.apple.com/documentation/quicklookui)提供 view / data 两种扩展接口及支持类型声明，没有找到可用于覆盖内置 HTML 优先级或交还下一提供器的公开控制入口。这是本机调查结论，不泛化为所有系统绝对不可能。

改成 [data-based provider](https://developer.apple.com/documentation/quicklookui/qlpreviewprovider)需另一套原型，且仅返回数据不能保证保留本轮要求的交互工具栏，也没有 HTML 分发成功证据。[旧 generator 路径已被 Apple 移除支持](https://developer.apple.com/documentation/macos-release-notes/macos-15-release-notes#Quick-Look)。本轮没有改 HTML 类型归属、默认应用或系统组件。不能把内部 renderer 已实现写成普通用户已能在 Finder 使用。

## 后续需求

陌生后缀和无后缀：优先有界、无损文本解码，失败恢复系统 Quick Look 行为。具体分发与错误后系统是否选择下一提供器尚未验证，不能仅注册 `public.data` 后假定自动回退成立。待办与验证边界见 [实施计划](superpowers/plans/2026-11-15-preview-plugin-only.md)。

原始构建、候选 / 安装清单、默认应用、路由、AX 和截图证据保存在 `.build/validation/preview-only-1220/`。机器摘要将 HTML 明确记为未完成，不把本轮整体记为全部需求通过。
