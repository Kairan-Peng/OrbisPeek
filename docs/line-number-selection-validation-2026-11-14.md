# 行号跨行选区修复

已修复并安装 0.1.1（1219）。真实 Finder 中，跨行拖选、全选和关闭换行后的反向拖选均只高亮正文，行号保持未选中。此次仅修改行号的一项兼容样式，已有复制算法保持。

## 复现与原因

用户在 Markdown 原文中跨行框选时，位于两端之间的行号显示蓝色选中底色；纯文本复制原本已正确过滤行号。源码、Markdown 原文、格式化 JSON 和 JSONL 共用同一种行号元素。

生产样式原本只有 `user-select: none`。本机实际 WKWebView 的 `CSS.supports('user-select', 'none')` 为 `false`，带 `-webkit-` 的版本为 `true`；行号的有效 `-webkit-user-select` 计算值为 `text`。跨行原生 `Selection.toString()` 夹入中间行号，而 `selectedPlainText()` 的过滤映射仍正确，因此出现“看上去选中、复制却不带行号”的差异。此结论来自本机生产 WebKit 对照，不泛化成所有 Safari / WebKit 都不支持标准属性；相关上游记录见 [WebKit unprefix 跟踪](https://bugs.webkit.org/show_bug.cgi?id=208677)。

## 修复与范围

`.line-number` 补充 `-webkit-user-select: none`，同时保留标准声明。生成资源同步更新。修复直接使原生文本选择排除行号，不通过透明选中底色掩盖问题，不改变行号 DOM、排版、正文选择或复制逻辑。

相对已安装的 1218，30 份生产运行时冻结中只有源 / 生成两份 CSS 改变。目录引导、只读授权、查找移除、原文切换、默认打开关联和后台组件状态保持。新增 `--checks line-selection` 仅属于开发用 probe，不向产品增加入口。

## 检查与真实 Finder 验收

- 实际离屏生产 WebKit 的 32 项检查：修复前 16 失败 / 16 通过，修复后 32 / 32 通过。覆盖 Swift、Markdown 原文、格式化 JSON、JSONL 的跨行、全选、换行关闭及精确复制投影；空行、缩进、制表符和正文数字保留。实际计算样式为行号 `none`、正文 `text`，换行确实在 `pre` / `pre-wrap` 间切换。
- 单独用程序构造的 DOM Range 仍能引用行号节点，这是正常 DOM 行为；修复后原生 `Selection.toString()` 为空、正文复制投影为 `null`。没有把 Raw Range 不能引用节点作为验收条件。
- 31 项既有 JavaScript 选区 / 复制投影检查通过。本轮未操作系统剪贴板，没有将投影检查写成 Finder 实体复制 / 粘贴重验。
- 真实 Finder 使用仓库忽略目录内的合成 Markdown，避免读取用户工作文档。跨行正向拖选的行号 4–13 保持灰色，正文有蓝色选区；⌘A 全选覆盖长行时，所有行号保持未选中；关闭换行后反向拖选，行号仍无蓝色底色。截图分别为 `finder-drag-wrap.png`、`finder-select-all.png`、`finder-drag-nowrap-reverse.png`。
- 初次尝试旧版 Finder 拖选前，用户切换了窗口，工具阻止了过期动作；该动作未执行，没有把它记录成实体基线。失败对照以用户提供的现象和实际 WebKit 的未修复资源为依据。随后安装修复版，重新载入合成文档完成了上述实体拖选。
- 安装前备份 1218，候选 / 安装签名、59 份文件、六份网页资源和 195 个精确预览类型核对通过；唯一偏好插件位于安装目录。最终只关闭明确属于本轮的 `fixtures` 测试标签，保留其他窗口 / 标签，并恢复用户最近使用的下载窗口。

## 证据与边界

实际 WebKit 基线 / 修复结果及源码冻结位于 `.build/validation/line-number-selection/`；本轮打包和 Finder 证据位于 `.build/validation/line-number-selection-1219/`，最终机器摘要为 `acceptance-summary.json`。

新 probe 保留可复现的 native Selection、计算样式、Raw Range 和精确复制投影结果，以防日后只改颜色或误删兼容声明。当前为本机 Debug arm64 开发安装，没有重验其他系统、Intel、发布公证、所有后缀或用户全部文档。
