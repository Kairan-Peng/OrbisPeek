# Preview Interface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 Finder 预览查找栏无法输入的问题，落实 A 单行图标工具栏与当前视图选区复制，并为 HTML 增加受限渲染/原文切换。

**Architecture:** 沿用 Swift 宿主和 Finder 扩展共用的 WKWebView 外壳。将查找、焦点与正文选区命令集中在小型交互模块中；HTML 使用受控、无脚本的隔离文档，并接入同一命令接口与已有图片资源边界。先修复真实 Finder 输入问题，再改工具栏；HTML 容器通过实际 WebKit 验证后才登记为支持格式。

**Tech Stack:** Swift 5 / AppKit / WebKit / QuickLookUI、原生 JavaScript、markdown-it、highlight.js、jsonc-parser、node:test / jsdom、XCTest、Python unittest。

---

## 执行约束与已批准设计

- 工作目录：当前项目仓库根目录。
- 当前工作区有并行的 OrbisPeek 品牌更名改动。实施前读取相关文件的最新 diff，只叠加本计划改动，不回退品牌、图标、样本或许可证变更。当前 app 产物名为 `OrbisPeek.app`；Xcode 工程/模块、`quicklook-probe`、bundle ID 与 `quicklook-app` URL 仍按各自现有名称使用，不做批量替换。
- 用户已批准 `docs/superpowers/specs/2026-11-11-preview-interface-design.md`，包括独立放大镜查找按钮、⌘F、仅隐藏复制按钮，以及查找输入焦点 bug。详细行为以该规格为准。
- 用户禁止未明确要求的分支、提交、推送与 PR；因此在当前 checkout 工作，本计划不含 worktree/branch/commit 步骤，覆盖技能中的相关默认习惯。保留已有文档改动和 `.superpowers/` 设计稿，不清理用户文件。
- 本计划的编写不是实施。以下命令和预期结果均是后续执行步骤，不代表本轮已经运行或通过。
- 不添加全局键盘监听、辅助功能权限或常驻 helper；不以宿主/交互稿成功代替真实 Finder 验收。
- 构建与测试使用开发候选。不得替换 `/Applications` 当前安装、安装发布包或改其他 provider 的 election；如 Finder 验收需要额外安装/登记授权，先准备好具体候选路径、版本和最小操作，再按规格范围取得授权，保留该验收未完成状态。
- 当前 `scripts/build --no-register` 仍会被 Xcode 短暂登记，完成后仅移除本次输出登记；不能称其为“从不登记”。

## 文件职责与修改地图

路径均相对上述工作目录。创建项只在对应任务执行时落盘。

| 文件 | 职责及改动 |
| --- | --- |
| `WebRenderer/src/preview-commands.js`（新增） | 查找开关/快捷键、IME、编辑控件例外、当前正文命令与事件绑定/解绑 |
| `WebRenderer/src/selection.js`（新增） | 正文全选与选区纯文本；源码 Range 映射、块/表格序列化，排除装饰内容 |
| `WebRenderer/src/html.js`（新增） | 惰性解析和限制 HTML、保留内嵌 CSS、图片重写、隔离文档挂接及正文适配 |
| `WebRenderer/src/renderer.js` | 保留格式渲染和状态，接入命令/选区/HTML，精简工具栏元信息；不整体重写渲染器 |
| `WebRenderer/src/index.html`、`styles.css` | A 单行布局、三个图标、查找关闭入口、严格主壳 CSP 与隔离容器样式 |
| `WebRenderer/src/markdown.js` | 本地图片 URL 支持当前加载 token，复用既有路径规则 |
| `Sources/QuicklookUI/PreviewWebController.swift` | 诊断/修复窗口内焦点、统一命令入口、受信主 frame 桥、当前加载生命周期、等待 HTML 完成 |
| `Sources/QuicklookUI/PreviewWebView.swift`（仅证据需要时新增） | 如 ⌘F 未送入 DOM，承载最小的窗口内 `performKeyEquivalent` 适配；不重放普通按键 |
| `Sources/QuicklookUI/HTMLPreviewDocument.swift`（新增） | 有界 HTML 文档准备结果、固定子 CSP、加载 token、准确资源路径与失效状态 |
| `Sources/QuicklookUI/PreviewResourceHandler.swift` | 精确 bundle 路径、当前受控子文档、token 绑定的受限图片、失效与诊断 |
| `Sources/QuicklookProbe/main.swift`、`scripts/validate-core.py` | 当前正文/子文档指标与显式 WebKit 交互检查；默认离屏 render 行为不变 |
| `Package.swift`、`Tests/QuicklookUITests/HTMLPreviewDocumentTests.swift`（新增测试目标/文件） | 测试纯资源准备、token/路径与 CSP 数据边界；不把它当键盘/Finder 测试 |
| `WebRenderer/test/renderer.test.js`、`selection.test.js`、`html.test.js`（后两项新增） | 有价值的查找/选区/解析/模式回归，复用现有 node:test/jsdom |
| `Sources/QuicklookCore/Resources/file-types.json`、`scripts/generate-types.py` | HTML 三个后缀、精确 UTType、html 模式与生成说明 |
| `Tests/QuicklookCoreTests/FileTypeRegistryTests.swift`、`Tests/Acceptance/test_type_declarations.py` | HTML 正向识别与其他类型/宽泛声明的负向回归 |
| `scripts/probe-routing.swift`、`scripts/validate-installed.py`、`Tests/Acceptance/test_validate_installed.py` | 更新 HTML 当前边界，保留其他禁止类型 |
| `scripts/make-fixtures.py`、`samples/fixtures/manifest.json`、`samples/fixtures/README.md`、`samples/fixtures/html/` | 当前 HTML 内容、安全与路由样例；明确审核同步受保护的生成文件 |
| `scripts/make-coverage-fixtures.py`、`Tests/Acceptance/test_make_coverage_fixtures.py` | HTML 组模板、可见 marker 与从清单推导的当前数量 |
| `scripts/report-finder-coverage.py`、`Tests/Acceptance/test_report_finder_coverage.py` | 新旧图标工具栏证据兼容、按批次 expected count 校验，不放松正文/provider 完整性 |
| `Config/Preview-Info.plist`、`docs/file-types.md`、`Sources/QuicklookUI/Resources/` | 通过现有生成器/renderer build 同步，不手写生成 bundle |
| `App/QuicklookApp.swift`、`README.md`、`README.zh-CN.md`、`docs/validation-plan.md`、`samples/coverage/README.md`、`docs/finder-coverage-reporting.md` | 更新当前能力与验收方法，保留明确标注版本的历史记录 |
| `docs/preview-interface-validation-2026-11-12.md`（新增） | 本轮失败复现、实际验证结果、候选版本/provider、截图与未验证项 |

除非生命周期证据表明确有扩展专属需求，否则不修改 `Extension/PreviewViewController.swift`。`TextLoader`、`LocalResourcePolicy`、目录授权能力和发布流水线不扩大。

## Task 1：优先修复查找输入被 Finder 截获

**Files:** Modify `Sources/QuicklookUI/PreviewWebController.swift`、`WebRenderer/src/renderer.js`、`index.html`；Create `WebRenderer/src/preview-commands.js`；Test `WebRenderer/test/renderer.test.js`；Record `docs/preview-interface-validation-2026-11-12.md`。

- [x] **Step 1：记录当前失败，确认实际 provider。** 在普通 workspace 目录的 `samples/fixtures/markdown/basic.md` 上使用 Finder Space。记录系统、应用路径/版本/build、预览文件路径及本项目主壳 URL `quicklook-app://bundle/index.html`。已复现点击查找及显式点击输入框后的键入均切换 Finder 所选文件；完整回归矩阵在新候选验收时继续执行。不对用户原文或查询做日志采集。
- [x] **Step 2：取得最小焦点诊断证据。** 仅在 Debug 或显式 probe 检查中记录加载 UUID、视图是否有 window、window key 状态、firstResponder/有限 responder 类名链、`makeFirstResponder` 返回值，以及 DOM `hasFocus/activeElement`、focus/input/composition 事件是否到达。只记合成样例的事件类别和长度。DOM input 为 activeElement 不能单独证明原生键盘焦点已进入 WebKit。
- [x] **Step 3：添加查找入口的失败回归。** 在现有 `page(t)`/`payload` 测试辅助函数旁增加以下测试；当前缺少 `renderer.commands`，应明确失败：

```js
test("find opens and repeated Cmd+F keeps input focused", async (t) => {
  const { document, window } = page(t);
  const renderer = createRenderer(document, window);
  await renderer.render(payload("# 预览\n\n正文", "markdown", "markdown"));
  renderer.commands.openFind();
  const input = document.getElementById("search-input");
  assert.equal(document.getElementById("search-bar").hidden, false);
  assert.equal(document.activeElement, input);
  document.dispatchEvent(new window.KeyboardEvent("keydown", {
    key: "f", metaKey: true, bubbles: true, cancelable: true,
  }));
  assert.equal(document.getElementById("search-bar").hidden, false);
  assert.equal(document.activeElement, input);
});
```

Run: `node --test --test-name-pattern='find opens' WebRenderer/test/renderer.test.js`。Expected：新增行为缺失导致失败，不是 import/语法或测试环境故障。

- [x] **Step 4：实现同一查找入口。** `preview-commands.js` 提供 `openFind/closeFind/toggleFind/handleKeyDown/bindDocument/dispose`；依赖由 renderer 注入当前正文 view、实际 search/clearSearch 与原生 focus 请求。放大镜点击调用 toggle，⌘F 调用 open；open 总是展开/聚焦，close 取消待执行 timer、清查询/高亮、收起并聚焦正文。输入框不随正文重绘而重建，关闭按钮及 `aria-expanded` 同步。由 `renderer.commands` 暴露该小型命令对象。此项仅表示命令层完成，不代表原生 Finder 焦点修复。
- [ ] **Step 5：按原生证据实施最小修正。** 若 first responder 未进入 webView，由受信主壳的显式用户操作请求在当前窗口执行 `makeFirstResponder(webView)`，随后恢复 DOM 查找焦点；桥新增 focus 动作仍检查精确主壳 URL、主 frame 和当前 UUID。异步回调必须确认文件未变、查找仍展开。若普通输入已进入 WebKit、只有 ⌘F 未到 DOM，再考虑 `PreviewWebView.performKeyEquivalent(with:)` 调用同一入口；未处理事件交回 `super`。不能预设某个 Quick Look flag 或 `makeFirstResponder` 一定解决问题。
- [ ] **Step 6：保留普通编辑与 IME。** 不重放普通 `keyDown`、退格、方向键，不强制激活其他应用/窗口。查找输入框保留 ⌘A/C/V；组合期间停止搜索 timer，不把 Enter 当匹配导航，不处理 Esc 收起。采用如下事件关系并按真实 WebKit 顺序验证：

```js
input.addEventListener("compositionstart", () => {
  composing = true;
  target.clearTimeout(searchTimer);
});
input.addEventListener("compositionend", () => {
  composing = false;
  scheduleSearch();
});
input.addEventListener("input", (event) => {
  if (!composing && !event.isComposing) scheduleSearch();
});
// keydown 的 Enter/Escape 分支先检查 composing 与 event.isComposing。
```

为组合期间不搜索/导航、普通 Esc、输入框编辑例外、切换模式后查询/焦点保留各添加对应行为断言；测试使用可控的搜索调度，不依赖任意睡眠。

- [x] **Step 7：更新 bundle 后做最小检查。** Run `npm --prefix WebRenderer run build`，再 `node --test --test-name-pattern='find|composition|search' WebRenderer/test/renderer.test.js`。Expected：命令/IME 回归通过；已有搜索文字不被当 HTML、行号不被搜索的测试继续通过。生成资源必须随源文件同步。
- [x] **Step 8：构建焦点修复候选。** Run `./scripts/build --no-register --derived-data .build/xcode-preview-interface-focus`。Expected：候选位于 `.build/xcode-preview-interface-focus/Build/Products/Debug/OrbisPeek.app`。记录实际版本/build、路径与资源；按本文执行约束及 Task 7 Step 3 的候选规则准备真实 Finder 验收，不能用当前安装的旧构建证明新修复。
- [ ] **Step 9：在获准的 Finder 候选上重复失败操作。** 分别验证按钮与 ⌘F、直接点击输入框、连续英文/中文拼音候选/标点、粘贴、退格与左右移动；观察输入确实进入本项目且 Finder 不做键入定位。记录失败与修复后证据。若仍失败，继续定位受支持的本地 responder 接入，不把 DOM 或宿主通过写为此 bug 已修复。

## Task 2：当前正文全选与选区纯文本复制

**Files:** Create `WebRenderer/src/selection.js`、`WebRenderer/test/selection.test.js`；Modify `renderer.js`、`preview-commands.js`、`renderer.test.js`；必要时最小调整原生 copy 桥，保留其权限边界。

- [x] **Step 1：固定当前正文接口。** 使用一个小对象 `{ document, root, kind, sourceText, focus, selectAll, selectedPlainText }`；kind 区分 source/rendered。sourceText 是当前已显示的规范文本，不是整份磁盘文件。默认正文在主 document；后续 HTML 只需提供相同接口，不创建另一套查找/复制逻辑。
- [x] **Step 2：添加真实选区的失败测试。** 用 JSDOM `Range` 与 `Selection` 建立选区后调用实际提取函数，不仅测试 stub 返回值。至少包括部分 token、跨高亮 span、跨行/空行、JSONL 错误徽标、段落、列表、代码块、表格、正文外节点和无选区。源码样例中同时放入大整数、缩进和真实 U+200B：

```js
const source = 'const id = 9007199254740993123456789;\n\n\tconst text = "你\u200b好";\n';
// 在实际渲染的 .source-line code 上全选正文后：
assert.equal(view.selectedPlainText(), source);
// 清除选区后触发 copy：现有 native bridge 的 messages 应仍为空。
```

Run `node --test WebRenderer/test/selection.test.js`。Expected：新提取/选择能力缺失时失败。测试必须核对完整文字，不能只断言不含行号。

- [x] **Step 3：实现源码 Range 到规范文本的映射。** 遍历选区相交的 `.source-line code`，按 DOM Range 在各 code 文本节点中的 UTF-16 偏移映射首尾行，再从 sourceText 提取并保留行边界。行号和 `.line-state` 从不参与。空行占位符改为可识别的结构或无文本方案；不能全局删除 U+200B，否则会损坏文件真实字符。支持末尾空行与只选择空白。
- [x] **Step 4：实现渲染选区的块级纯文本。** 仅序列化选区与正文根相交的内容；段落/标题/列表项用合理换行，代码块保留空白，表格单元格用 tab、行用换行。排除行号、状态、`.blocked-image`、脚本/样式/模板及工具栏。保持选区边界，不用整篇 Markdown/HTML 或整个 root.textContent 替代。
- [x] **Step 5：接入标准 copy 与限定正文的全选。** 正文 `copy` 事件在有有效选区时写 `text/plain`，必要时经受信主 frame 的既有原生桥落剪贴板；对编辑控件直接交回原生行为。无选区/纯提示选区既不复制整篇也不清空剪贴板。⌘A 仅在正文上下文建立正文 Range，查找输入仍只全选查询。不同时在 keydown 和 copy 事件复制两次。
- [x] **Step 6：更新旧复制测试。** 替换“点击复制按钮收到全部 JSON”测试为真实选区复制的桥消息断言；覆盖 JSON 格式化/原文、MD 渲染/原文、JSONL、代码。保留 `renderDocument.copyText` 中对当前源码规范文本仍有价值的部分，不用它提供渲染态整篇复制。复制按钮及整篇 handler 在 Task 3 移除。
- [ ] **Step 7：检查宿主与 Finder 实际粘贴。** Run `npm --prefix WebRenderer run build`、`node --test WebRenderer/test/selection.test.js WebRenderer/test/renderer.test.js`。随后在真实正文拖选并复制到纯文本接收处，核对跨行、空行、代码块/表格、中文和大整数。分别测试正文 ⌘A、输入框 ⌘A/C/V、无正文选区时剪贴板保持不变；结果分清 DOM、宿主和 Finder。

## Task 3：落地 A 单行工具栏和三个图标

**Files:** Modify `WebRenderer/src/index.html`、`styles.css`、`renderer.js`、`preview-commands.js`、`WebRenderer/test/renderer.test.js`。

- [x] **Step 1：按已选交互稿修改结构。** 对照 `.superpowers/brainstorm/27220-1794410108/toolbar-layout-a-search.html`：文件名主体/扩展名单独布局，格式/编码/大小/行数紧跟，右侧顺序为模式、换行、放大镜查找。删除复制按钮及对应 handler；不删除 JSONL 模式切换等现有能力。保留现有查找元素 ID，方便行为测试与命令复用。
- [x] **Step 2：使用固定可信 SVG 图标。** 代码/眼睛、文字折返、放大镜采用静态资源或固定内联 SVG；不拼接文件内容。模式更新图标同时更新 `title/aria-label/aria-pressed`，查找更新 `aria-expanded`；现有“下一处”改下箭头、关闭改 ×，都保留中文说明与快捷键提示。纯代码隐藏模式按钮；MD/HTML 渲染态禁用换行，文本态默认开启。
- [x] **Step 3：收紧布局，不写外观镜像测试。** 工具栏 nowrap；文件名主体 ellipsis、扩展名不收缩，元信息较弱，按钮尺寸与位置稳定。按可用空间依次隐藏编码、行数/记录数、格式，完整信息通过 title/辅助文本保留。移除当前窄于 520px 时把操作另起一行的规则。只保留有意义的控制状态/可访问名称测试。
- [x] **Step 4：实际检查布局与搜索展开。** Run `npm --prefix WebRenderer run build`、`npm --prefix WebRenderer test`。在 420/520/920px、长/普通文件名、深浅色、渲染/源码、搜索展开下查看工具栏和正文；保存代表性截图。确认三个图标不被挤出、文件名保留扩展名、查找展开不抢掉编辑焦点。细节以实际效果调整，不强行复制 mock 的像素值。

## Task 4：先验证 HTML 隔离容器与命令边界

**Files:** Create `Sources/QuicklookUI/HTMLPreviewDocument.swift`、`Tests/QuicklookUITests/HTMLPreviewDocumentTests.swift`；Modify `Package.swift`、`PreviewResourceHandler.swift`、`PreviewWebController.swift`、`WebRenderer/src/index.html`、`Sources/QuicklookProbe/main.swift`、`scripts/validate-core.py`。此任务先使用固定合成 HTML，不注册类型，不加载用户 HTML。

- [x] **Step 1：建立受控资源状态及失败测试。** 新增只依赖 Foundation 的有界准备/路由状态，由 `QuicklookUITests` 通过 `@testable import QuicklookUI` 测试：当前 UUID 路径可取，旧 UUID/错 host/错路径/越界/超预算被拒绝，invalidate 后不可取；固定子 CSP 不含文档脚本许可。测试真实状态解析，不 mock 它自己的返回值。Run `swift test --filter HTMLPreviewDocumentTests`，先见到预期缺失能力失败。
- [x] **Step 2：实现精确端点与失效。** 主壳 URL 保持 `quicklook-app://bundle/index.html`；子文档为 `quicklook-app://bundle/document/<UUID>/content.html`。bundle 静态资源改为精确 host/path 白名单，不能继续只看 lastPathComponent。每次 showFile 一开始、取消、关闭/换文件时立即 invalidate 文档与 token；资源回调校验当前 UUID，不等新文件加载完才替换。
- [x] **Step 3：建立受信准备握手。** 给受信主壳增加有回复的 HTML 准备消息入口：精确校验主 frame、`quicklook-app://bundle/index.html`、当前 requestID，限制准备文本不超过 2 MiB UTF-8；返回当前受控子 URL。可用 `WKScriptMessageHandlerWithReply` 及弱代理，保持现有 copy 桥的主 frame 检查。子文档不允许直接调用此入口。超限、失效、错误来源必须返回明确失败，不保留旧文档。
- [x] **Step 4：固定父/子策略。** 主 CSP 继续 `script-src 'self'; style-src 'self'`，frame-src 仅开放 `quicklook-app://bundle/document/`，其余既有禁止项保留。子文档固定策略为：

```text
default-src 'none'; script-src 'none'; style-src 'unsafe-inline';
img-src quicklook-resource:; connect-src 'none'; font-src 'none';
media-src 'none'; frame-src 'none'; object-src 'none';
base-uri 'none'; form-action 'none'
```

iframe 仅设 `sandbox="allow-same-origin"`，不允许文档脚本、表单、弹窗或顶层导航。通过响应头或先于文档内容的固定 meta 交付子 CSP，采用实际 WebKit 验证有效的方式。不能把 `srcdoc` 当作独立策略的等价替代。

- [x] **Step 5：扩展显式 probe 检查。** `quicklook-probe render FILE --checks html-container --output JSON` 在默认主壳渲染后，用受信测试代码准备合成子文档并采集实际 DOM 事实：contentDocument/Selection/Range/TreeWalker/滚动访问、子脚本/事件属性不执行、样式不污染主壳、旧 token 与子 frame 桥被拒绝。记录子 click/keydown/copy 回调在无脚本 sandbox 下被抑制的事实；验证原生命令进入主壳后操作子选区、全选、标记/滚动与父查询框焦点的替代路线。使用 loopback 请求计数端点及允许 loopback 图片的合成 WebKit 正对照，检查严格子 CSP 下 remote CSS/img/font 请求为零；只看“图片没显示”或 native HTTP 正对照不算 WebKit 网络禁止证据。`validate-core.py --include-preview-interactions` 启动/关闭该合成本地计数端点并校验 probe JSON。
- [x] **Step 6：运行技术检查并记录决策。** Run `npm --prefix WebRenderer run build`、`swift build --product quicklook-probe`、`python3 scripts/validate-core.py --include-preview-interactions --output .build/validation/preview-container.json`。Expected：选择后的主壳命令路线与安全边界检查通过，默认旧核心用例继续通过；回调抑制是已测平台约束而非假称成功的项目。离屏 probe 不被写成真实键盘/IME/Finder证据。
- [x] **Step 7：按证据确定后续容器实现。** 2026-11-12 已在 `.build/experiments/html-container-probe/` 完成独立真实 WebKit 实验：同源 DOM/CSS/Selection 可访问，但子文档各 content world 的事件回调都被无脚本 sandbox 抑制；子 `.page` 执行返回 WKErrorDomain 4。采用原生明确命令 → 受信主壳 → 同源子 DOM 的路线，不再依赖子文档事件监听。主壳直接提取选区、全选、TreeWalker/Range 标记与滚动、聚焦父输入框均已通过离屏实验，实体按键/剪贴板/Finder 留待生产接入验收。保留无脚本 sandbox、独立子 CSP 与主 frame 桥检查，不开放文档脚本或网络。独立实验不等于 Task 4 整体集成完成。

## Task 5：实现静态 HTML、默认渲染与当前正文命令

**Files:** Create `WebRenderer/src/html.js`、`WebRenderer/test/html.test.js`、`samples/fixtures/html/{preview.html,preview.htm,preview.xhtml,blocked-resources.html}`；Modify `renderer.js`、`preview-commands.js`、`markdown.js`、`PreviewWebController.swift`、`PreviewResourceHandler.swift`、`Sources/QuicklookProbe/main.swift`、`scripts/validate-core.py`。

- [x] **Step 1：先写惰性解析与限制的失败测试。** 在无 browsing context 的独立 HTMLDocument 中完整解析，再使用 template 的 inert owner document 重建允许的静态元素/属性（根属性保留修正后路线，实际惰性网络/脚本门槛已通过），禁止解析阶段自动请求资源；在实际 WebKit 检查阶段也验证这一点。保留标题、段落、列表、表格、代码、链接、style 与静态 style 属性；移除 script、on*、base、文档 CSP/refresh、嵌套 frame、插件、表单/自动媒体、contenteditable，清理 srcset/picture/source 等旁路。测试大小写/畸形标签、编码后 URL 与混合属性，不靠正则整体清洗 HTML。

```html
<h1>HTML 正文</h1><style>h1 { color: rgb(18, 52, 86) }</style>
<img src="assets/local.png" onerror="parent.untrustedRan=true">
<img srcset="https://example.invalid/a.png 2x">
<script>parent.untrustedRan=true</script>
<meta http-equiv="refresh" content="0;url=https://example.invalid/">
<form action="https://example.invalid/"><input name="secret"></form>
```

Expected：正文与内嵌样式保留，主动行为移除；剩余不可信 CSS 仍被固定子 CSP 和隔离容器约束。Run `node --test WebRenderer/test/html.test.js`，先确认新增能力缺失导致失败。

- [x] **Step 2：复用并绑定图片策略。** `localImageURL` 继续拒绝绝对/远程/父目录/错误编码路径，在 native payload 有 resourceToken 时生成 `quicklook-resource://local/<UUID>/<relative-path>`。Markdown 与 HTML 都使用当前 token，原生不接受失效 token，避免旧 iframe 的迟到请求按新目录解析。诊断中的 path 仍为原相对路径，可另记 token。HTML 的 img 重写后才进入子文档；不支持的 CSS URL/外部样式/字体被子 CSP 阻断，不新增 CSS 网络加载器。
- [x] **Step 3：挂接隔离文档并等待完成。** 主壳只接收准备结果和 URL，不把文件 HTML 放进主 #content.innerHTML。iframe load 后取当前正文适配；主壳安装自己的监听并经原生入口接收 HTML 命令，直接操作同源子 DOM，不依赖无脚本子文档回调。主壳负责查找栏和原生桥。`renderer.render()` 统一返回 Promise，非 HTML 仍尽快完成；更新现有 DOM/bundle 测试使用 await。原生现有 callAsyncJavaScript 等待该 Promise，HTML ready 或安全退回后才发送 onRender/回执。加载超时、资源准备失败、旧 UUID 的迟到 load 不能覆盖新文件。
- [x] **Step 4：接通各状态。** html 加入 renderer 的模式白名单，默认子文档渲染；原文态使用既有 HTML 高亮（languages.js 已注册 html alias）。切回渲染重用当前受控准备，不保留跨文件模式。当前正文接口在 HTML document 与主文档之间切换，绑定/解绑主壳与原生命令入口；不能指望 iframe 事件冒泡或子文档回调执行。⌘F 将焦点交给主壳查询框，⌘A/C 针对 HTML 选区，Esc 遵循查找/IME规则。查询保留并在新正文重搜。针对窗口内原生命令要覆盖 Copy/Select All/Find 的标准 responder 入口与命令键，编辑查询时仍执行标准编辑语义；外链通过受控 native navigation delegate 处理。
- [x] **Step 5：限制导航与恢复。** 原生区分主壳首载和当前 token 子文档首载，拒绝自动导航/刷新、表单和其他 token；外链仅在真实 linkActivated 且来源为当前受控视图时交给外部应用。`javascript/file/data/相对文件` 不打开；文内锚点只在当前正文滚动。失败显示简短原因并提供原文，不放宽策略。
- [x] **Step 6：扩展核心 probe/用例。** 主壳和当前正文分别报告 text、images、script/事件执行事实与资源诊断；主壳一个可信 renderer script 与子文档无脚本分开统计。HTML case 必须读取子正文而非主 body.innerText 空壳。新增默认/原文、样式隔离、坏资源、授权/无授权/撤销、子视图命令及切换文件迟到回调回归；保留全部既有 JSON/JSONL/编码/大文件检查。
- [x] **Step 7：执行最小验证。** Run `npm --prefix WebRenderer run build`、`npm --prefix WebRenderer test`、`swift test --filter HTMLPreviewDocumentTests`、`swift build --product quicklook-probe`、`python3 scripts/validate-core.py --include-preview-interactions --output .build/validation/preview-html.json`。Expected：HTML正文与模式正确，原生资源/子 CSP 边界实测通过，旧核心回归不下降。此时仍不宣称 Finder 已接管 HTML。

## Task 6：HTML 类型、样本与验收工具配套

**Files:** 按文件地图修改类型清单/生成器、Swift/Python 类型测试、安装/路由检查、fixtures/coverage/report 脚本与测试；生成 `Config/Preview-Info.plist`、`docs/file-types.md`。

- [x] **Step 1：先添加类型失败断言。** Swift 明确断言 `sample.html/sample.htm/sample.xhtml` 的 mode/language 都为 html。把 HTML 从原系统排除测试移出，继续拒绝 TXT/PDF/Office/CSV/SVG、宽泛 `public.data/public.text/public.plain-text/public.source-code/public.xml-based-text` 及既有冲突媒体类型。Python 增加精确 HTML UTType、没有改默认打开关联的回归。Run `swift test --filter FileTypeRegistryTests`、`python3 -m unittest discover -s Tests/Acceptance -p 'test_type_declarations.py' -v`，Expected：新增 HTML 断言先失败。
- [x] **Step 2：添加一个 HTML 组并更新生成规则。** 清单新增 html/htm/xhtml、mode=html、language=html；在实施机用真实文件的 contentType 核对 public.html/public.xhtml 精确语义 UTI，不为了 XHTML 注册宽泛 XML 父类型。生成器移除 HTML 明确排除并允许 html 模式，更新当前边界文案；同步 probe-routing.swift 与 validate-installed.py 的 HTML 保留/禁止集合。其余类型政策不变。
- [x] **Step 3：生成并检查。** Run `python3 scripts/generate-types.py`、`python3 scripts/generate-types.py --check`。Expected：三种后缀、一个新组；当前应从清单计算得到 230 后缀/87 组/56 文件名规则，不能把数字写进历史结果。检查生成 plist 仅新增预期声明且 handler rank/default application 未被更改。更新 `Tests/Acceptance/test_validate_installed.py` 的正负案例。
- [x] **Step 4：修正 fixture 生成与旧当前说明。** make-fixtures.py 不再把 HTML 放进本轮“系统保留”用例；旧 `samples/fixtures/text/system-preview.html` 可保留为历史输入，当前新样本位于 html/，含同目录合成光栅资源。明确审核并同步 manifest.json/README.md：该脚本 `write_missing` 会拒绝覆盖有差异文件，不能依靠反复重跑绕过；不删除或覆盖用户文档。Run `python3 scripts/make-fixtures.py --inspect`，Expected：全部当前 fixture 可结构检查，HTML 当前预期为 preview。
- [x] **Step 5：更新 coverage 模板及动态计数。** 在 make-coverage-fixtures.py 新增 html TEMPLATES，确保组键集合与 registry 完全一致。生成 HTML 的正文 marker 放在前三行且实际可见，不藏在注释/head/title。把当前 fixture 测试硬编码 227/86/85/紧凑组数改为从当前清单推导，并单测 HTML 语法和可见 marker。Run `python3 -m unittest discover -s Tests/Acceptance -p 'test_make_coverage_fixtures.py' -v`，Expected：新清单完整覆盖，原格式代表性检查仍通过。
- [x] **Step 6：让覆盖判定识别新旧工具栏。** report-finder-coverage.py 不再对新 UI 强制存在“复制”按钮；仍要求精确主壳 URL、对应文件标题、本扩展可访问的图标功能名称和实际正文 marker。新 HTML 必须位于同一主壳 AX 子树且有模式切换证据。为旧文字工具栏、新图标工具栏、系统 HTML、只图标无正文、错误文件、缺少上下文分别加正负测试；保留旧观察兼容，不能把任意 quicklook-app URL 判为成功。
- [x] **Step 7：按批次校验完整性。** reporter 的 CLI、manifest 检查与 boundary gate 使用同一个显式 expected_count；保留旧 227 profile，新批次以新清单数量为准。只改 CLI 默认值或把完整性门槛降低都不行。新增非 227 完整批次、少一项/重复项、旧批次兼容测试；保留 registry hash 校验，不能篡改旧报告 hash 来“修复”历史数据。
- [x] **Step 8：跑配套回归。** Run `swift test --filter FileTypeRegistryTests`、`python3 -m unittest discover -s Tests/Acceptance -p 'test_*.py' -v`、`python3 scripts/make-coverage-fixtures.py --output .build/finder-coverage-preview-interface`。Expected：当前语料生成在独立新目录，现有 `docs/finder-coverage.md/json`、0.1.1 (12) 的 227 项历史证据不改写；该脚本已有明确的 `--output` 参数，无需新增 CLI。

## Task 7：构建、真实 Finder 验收与当前文档同步

**Files:** Modify 当前 README/引导和验证文档；Finalize `docs/preview-interface-validation-2026-11-12.md`、新批次 `.build/validation/preview-interface/` 证据与已批准的计划登记状态。

- [x] **Step 1：执行完整自动检查。** Run `npm --prefix WebRenderer run build`、`./scripts/test`、`python3 -m unittest discover -s Tests/Acceptance -p 'test_*.py' -v`、`swift build --product quicklook-probe`、`python3 scripts/validate-core.py --include-preview-interactions --output .build/validation/preview-interface/core-results-1203.json`。先创建输出目录。Expected：生成检查、JS、Swift、Python、真实 WebKit 用例全部通过；新脚本选项在 Task 4/5 已实现。
- [x] **Step 2：构建可核对候选。** Run 使用既有 Developer ID / Team 的 `./scripts/build --directory-access --no-register --derived-data .build/xcode-preview-interface-focus CURRENT_PROJECT_VERSION=1203`。Expected：可运行开发构建，路径沿用已获准的 `.build/xcode-preview-interface-focus/Build/Products/Debug/OrbisPeek.app`，版本 0.1.1（1203）；记录实际代码/资源与候选身份，源码版本不变。App Group 图片权限验证仅使用既有获准签名配置，不创建证书或扩大授权，不顺手打包/上传公证。
- [x] **Step 3：为 Finder 测试准备具体候选。** 核对当前安装和实际 provider；只在已有授权范围内使用候选，不默认替换当前安装或改其他插件。若需额外安装/登记，将候选路径/版本和拟变更写明后交由用户完成或明确授权。没有新候选的真实 Finder 结果，以下项目保持未验证，不能借用旧构建结果。
- [ ] **Step 4：查找焦点专项。** 对普通 workspace 中的 MD/JSON/源码及 HTML，首次打开和关闭重开分别测试：放大镜展开→直接输入、直接点击输入框、正文→⌘F、展开时再⌘F、粘贴/退格/方向键、中文组合中 Enter/Esc、组合完成后的 Enter/Shift+Enter。查询必须进入本项目，Finder 选中项不做键入定位。
- [ ] **Step 5：模式与关闭的焦点专项。** 查询后切换渲染/原文，继续输入并在新正文重搜；按钮收起与 Esc 关闭清高亮、焦点回正文，再次 Esc 保留系统行为。换文件/关闭后没有迟到回调抢焦点；切到 Finder 其他窗口输入不被旧预览截获。
- [ ] **Step 6：实际选区复制专项。** 对 MD 渲染/原文、JSON 格式化/原文、JSONL、普通源码与 HTML 两态，拖选后 ⌘C 粘贴到纯文本接收处，核对跨行/空行、代码块/表格、中文、大整数、真实 U+200B。正文 ⌘A 不混入工具栏/提示/行号；查找框的 ⌘A/C/V 只编辑查询；无正文选区时剪贴板不变。
- [ ] **Step 7：HTML provider 与资源专项。** HTML/HTM/XHTML 必须实际看到本项目主壳与可工作的模式切换。验证子文档内嵌样式不影响外壳，主动脚本/导航/表单/远程资源受限，本地光栅图片授权/无授权/撤销后重开及超预算行为与 MD 一致。宿主或类型注册匹配不能替代此项。
- [ ] **Step 8：视觉与可访问性专项。** 420/520/920px、普通/长文件名、深浅色、渲染/源码与搜索展开状态留代表性截图。三个图标可操作且有准确名称/状态，工具栏保持一行，扩展名和必要元信息可读；文件信息通过完整悬浮/辅助文本可取得。
- [x] **Step 9：记录新结果，不改写旧证据。** 新记录区分 DOM、宿主 WebKit、真实 Finder，并写明路径/版本/provider、通过/失败/未验证、实际粘贴文字核对与截图。旧的 227 后缀报告、beta-validation-2026-11-11.md 和 validation-results.md 保持历史事实；新的完整后缀批次只有真的逐项运行后才能称为全量通过，不是本次 UI 改动的自动结论。
- [x] **Step 10：更新当前产品说明与交付核对。** README/README.zh-CN 当前能力、App/QuicklookApp.swift 欢迎页“HTML系统预览”文案、docs/validation-plan.md、samples/coverage/README.md、docs/finder-coverage-reporting.md 同步新能力与工具栏规则；保留标注版本的历史结果。把 docs/implementation-plan.md 指向此详细计划；只有实际完成的项打勾。Run `git diff --check`，检查 `git diff --stat` 和生成资源差异；不创建分支、提交、推送或发布。


2026-11-12 晚间状态：用户新增“替换安装并进行校验”授权，1203 已安装至 `/Applications/OrbisPeek.app`，原版备份并移到可恢复废纸篓；Step 3 候选身份 / 安装 / 启用核对完成。开发安装检查、七种实际文件的默认打开应用前后对照、JSON 系统回执与 Finder Markdown 渲染 / 原文切换通过。用户实体键盘确认查找输入仍失败；HTML/HTM/XHTML 及全新文件名 HTML 仍为系统 file:// 预览，Step 4 / 7 不得计为通过。实际复制、完整 IME / 快捷键矩阵和本轮沙盒授权 / 撤销尚未验收。测试预览 / 自建标签页已关闭，原六页与当前选中项恢复。自动与离屏证据继续保留；未以安装成功覆盖实际失败。

## 任务依赖与结束条件

1 的命令层完成规格/质量审查后，2 的纯选区逻辑已独立完成。2026-11-12 已获准临时登记并在真实 Finder 对照窗口 key、根视图、原生控件与 didFinish 时机；均未通过 CUA 原生输入对照；该工具未承诺硬件键盘等价，真人对照仍待确认。所有实验性自动聚焦/根视图/原生字段代码移除，该早期诊断的原登记和 Finder 标签页已恢复。后续 1201 真人对照因 Mac 锁定退出，登记已恢复，但本轮新增一页和原 AppWink 快速查看仍待解锁后恢复。继续执行不依赖宿主键盘路由的 3 与 4/5/6，P0 原生修复、实体快捷键和真实 Finder 验收仍保持未完成，不得以这些独立任务完成代替。2 → 3；4 的容器技术验证也可独立推进。5 依赖 2、4；6 依赖安全 HTML 已实现；7 汇总所有任务。等待输入不等于获得候选登记授权。

执行结束报告必须说明：查找输入 bug 是否在真实 Finder 修复，按钮/快捷键是否均验收，复制文字是否核对，HTML 是否真由本扩展呈现，以及哪些平台/签名/图片/路由场景仍未验证。测试通过、成功构建或回执只证明各自层级，不代替未执行的 Finder 检查。

后续诊断记录：当前实体输入失败已确认；尚未找到已验证的公开 Quick Look 焦点交接开关，不能仅凭系统警告宣布平台绝对不支持。此前原生字段对照只有 CUA 证据，如后续继续定位，可单独安排普通点击聚焦的原生 NSTextField 实体对照，先区分 WebKit 与宿主路由，不作为未经验证的生产修复。HTML 后续定位保留精确 UTI 和默认打开关联边界，不通过宽泛类型或全局重置制造表面通过。
