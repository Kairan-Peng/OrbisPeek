# 预览交互实施与验证记录

日期：2026-11-12。本记录区分旧安装的失败复现、自动测试、宿主 WebKit 与新候选真实 Finder 验收。尚未执行的项目不视为通过。本文的按键序列均由 CUA `App.pressKey` 生成；工具没有公开承诺保留宿主 key window 或等同硬件键盘，故这些失败是自动化输入对照，真人键盘结果尚待单独确认。用户对旧安装的原始 bug 报告另行保留，不能由自动化失败推导所有候选真人输入均失败。

## 旧安装：Finder 查找输入失败已复现

- 环境：macOS 27.0.1 / arm64；旧宿主可执行文件 SHA-256 为 `a0f020337f8dfb53327c6321a5a025c1ed40cbbbd37c45030b93dde8d61556cb`。
- 安装：`/Applications/Quicklook.app`，0.1.1（12）。只读 PlugInKit 查询显示该 bundle ID 当前只有这一份登记且为 preferred；尚未替换安装或调整 provider。
- 样本：仓库 `samples/fixtures/markdown/basic.md` 与 `resources.md`，通过新建的 Finder 标签页打开；原有六个标签页保留。
- Provider 证据：Quick Look AX 主壳为 `quicklook-app://bundle/index.html`，标题先显示 `basic.md · Quicklook`，有本项目原文、换行、复制、查找工具栏与对应正文。
- 操作一：点击查找，出现空搜索框；AX 焦点仍报 Quick Look window。逐个发送原生 `j/s/o/n` 按键，查询没有得到输入，预览改为 `resources.md`。
- 操作二：在 `resources.md` 展开查找，显式点击搜索输入框，再逐个发送原生 `b/a/s/i/c` 按键；预览改为 `basic.md`，搜索框仍为空。截图可见输入框蓝色轮廓和插入点，这不能单独证明原生键盘焦点进入了 WebKit。
- 结论：用户报告已在真实 Finder 独立复现；DOM 显示焦点与实际键入去向不一致。根因仍需原生 window/responder 诊断，不把现象直接当作某个 AppKit 属性的已证实缺陷。

本地证据：`.build/validation/preview-interface/finder-find-baseline.txt`、`finder-find-baseline.jpg`。这些记录的是旧版失败状态，不是新实现通过。

## 实施状态

- 查找命令与 IME 回归：命令层已通过独立规格/质量审查，根代理复跑 39/39 renderer tests 通过；包含受控时钟、组合中按钮保护、关闭/换文件/迟到回调取消。此结果不是 Finder 原生输入修复证据。
- 原生焦点修复：待诊断候选和真实 Finder 对照，不以 DOM/宿主成功代替。
- 当前正文选区复制：纯逻辑实现已通过独立规格/质量审查；根代理及审查者分别验证了测试。当前全套 renderer/selection 共 65/65 通过。A 图标工具栏、HTML 生产接入、类型/报告配套尚未完成。
- 最终自动检查、候选构建与 Finder 回归：尚未完成。

## 验收门槛

新候选必须分别通过放大镜与 ⌘F 两条入口的真实输入、中文组合、粘贴与编辑；不得触发 Finder 键入定位。复制必须实际粘贴核对，HTML 必须由本扩展显示且通过隔离/资源与模式切换检查。完整步骤见 `docs/superpowers/plans/2026-11-11-preview-interface-implementation.md`。

## HTML 独立隔离实验

独立 harness 只写 `.build/experiments/html-container-probe/`，未改生产文件、登记或安装。真实 WKWebView 中，受控同源端点与无脚本 sandbox 可以保留内嵌 CSS，主壳能够读取子 DOM、Selection、Range、TreeWalker 并滚动；子文档 click/keydown/copy 回调在各 content world 中均被抑制，不能直接沿用主壳事件处理方案。

替代路线已在离屏动作层验证：原生命令调用受信主壳函数，由主壳获取子选区、限定正文全选、创建查询标记与滚动，并聚焦父查询输入框。子脚本/事件属性仍不执行，旧 token 与子 frame 原生桥请求被拒绝。此结果不证明实体快捷键、实际剪贴板或 Finder 已通过。

网络检查包含 WebKit 传输正对照：同一合成容器仅允许 loopback 图片时有实际请求且图片解码；随后两种严格子 CSP（响应头/首个 meta）均观察到零请求。详细事实、脚本和 JSON 位于该目录的 `REPORT.md`、`summary.json` 及每种策略结果，可用 `python3 .build/experiments/html-container-probe/run.py` 重现。

## 当前选区逻辑的真实 WebKit 检查

- 独立 harness 使用生产 bundle 的固定快照；最终 renderer SHA-256 为 `17847a47611afdcc55f3906a19b6258280e9f5f82f9f4012427b4dd020ae52ae`。
- 最终 19/19 Range/Selection 检查通过：MD 渲染/原文、跨高亮 span、源码空行/缩进/末尾换行/真实 U+200B、JSON 大整数两态、表格空单元格/部分选区、装饰-only 表格，以及真实 Markdown 硬换行 `one  \ntwo` 对应可读文本 `one\ntwo`。
- 直接调用 WebKit 的原生 `copy:` responder 动作，三项检查都产生 `isTrusted=true` 的 copy 事件。正文写入预期 text/plain；仅图片受限提示和仅行号两项被取消且不写数据，测试 marker 保持不变。
- 原剪贴板只在进程内按全部 item/type/Data 保存并精确恢复，未在结果中输出用户剪贴板内容。
- 这证明了真实引擎的选区和 Copy 动作逻辑，不证明实体 ⌘C、IME 或 Finder 的键盘路由；后者仍未完成。

证据：`.build/experiments/selection-webkit/REPORT.md`、`final/results.json`、`final/bundle-manifest.json`，早期 baseline 保留。生产代码与最终测试快照的 renderer hash 一致。

## 开发候选：真实 Finder 焦点诊断

用户已明确允许仅临时登记 `.build/xcode-preview-interface-focus/Build/Products/Debug/OrbisPeek.app`，用于本轮 Finder 诊断及后续修复验证；不替换 `/Applications` 安装、不调整其他插件，测试后恢复原登记。当前测试期间只暂时移除同 bundle ID 的旧登记，旧安装文件未改动。

- 候选使用已有 Developer ID 签名重建，`codesign --verify --deep --strict` 通过，版本 0.1.1（12）。签名构建日志为 `.build/preview-interface-focus-signed-build.log`。先登记包含 app，再登记 appex；只登记 appex 的首次请求被系统拒绝。先前 ad-hoc 候选 fallback 的原因没有得到独立证明，不归因于签名。
- Finder 实际进程 PID 33559 的可执行路径位于上述候选；AX 主壳为 `quicklook-app://bundle/index.html`，标题 `focus-diagnostic-20261112.md · OrbisPeek`，合成正文可见。
- 渲染完成时：`NSServiceViewControllerWindow` 已挂接，`canBecomeKey=true`，`key=false`，`acceptsFirstResponder=true`，`needsPanelToBecomeKey=true`；firstResponder 为服务窗口。
- 点击查找后：原生 firstResponder 链已从 `WKWebView` 开始，DOM `activeElement=search-input`、`hasFocus=true`，但窗口仍 `key=false`。逐个发送CUA 原生按键 `n/e/e` 后查询没有输入，Finder 选择与预览切换到 `registration-before.txt`。
- 结论：最小诊断候选仍复现 bug，现有证据支持先验证窗口 key 状态修正；并不支持重复设置已经为 true 的 `needsPanelToBecomeKey`。修正与新候选验收尚未完成。

内容无关的焦点日志为 `.build/validation/preview-interface/find-focus-candidate-initial.log`；登记前快照为 `registration-before.txt`，路由审计为 `route-audit.md`。测试登记与本轮新增 Finder 标签页将在诊断结束后恢复。

### 窗口 key 状态假设：未修复

同一路径的签名候选 PID 35656，在最终文件/查找代次校验后同步调用 `makeKey()` 和 `makeFirstResponder(webView)`。实际日志在调用前、调用后及下一主线程轮次均为 `key=true`，`makeFirstResponder=true`，DOM 仍聚焦查询框；CUA 原生按键 `n/e/e` 仍使 Finder 切换到 `registration-before.txt`。另以实际鼠标坐标点击查找和输入框再键入 `n/e`，结果相同。

因此该修正不足以解决 bug，不能保留为“已修复”的证据。扩展可执行文件 SHA-256 为 `7800f062148cc03692b0ea1bcde8fed502fe15fb60ab43a5c6dfa732e8ffa921`；构建日志 `.build/preview-interface-focus-key-build.log`，原生日志 `find-focus-candidate-key.log`。下一次只检验导出给 Quick Look 的根视图 responder 能力，移除未奏效的 `makeKey()`；远程宿主是否采纳根视图能力仍待实测。

### 根视图与原生控件对照

- 导出根视图返回 `acceptsFirstResponder=true`、`needsPanelToBecomeKey=true` 的单一候选 PID 37001 仍失败；服务窗口 key、WebKit responder 和 DOM 状态均正常，键入 `n/e` 仍切换 Finder 文件。祖先链中的系统 `QLUIServiceView`、ViewBridge jail 为 false；没有修改这些系统对象。日志为 `find-focus-candidate-root.log`，构建为 `.build/preview-interface-focus-root-build.log`。该根视图覆盖随后移除。
- 临时编译条件 `DEBUG QUICKLOOK_NATIVE_FOCUS_PROBE` 的候选 PID 38110 在 WebKit 上方增加原生 `NSTextField`。AX 与截图中字段存在；分别使用 AX 目标和实际鼠标坐标点击后，仍没有字段编辑事件，`n/e` 仍去往 Finder。日志为 `find-focus-native-field.log`，构建为 `.build/preview-interface-focus-native-field-build.log`。这是一项待移除的诊断控件，不是产品界面。
- 键盘正对照：同一 Finder 进程的“前往文件夹”原生路径字段中，相同 `n/e` 逐键操作实际得到 `ne`；随后取消表单，未打开路径或改动文件。这排除了该按键序列完全没有产生输入的情况，但不将其推广为所有 UI 自动化行为的证明。
- 直接导出可编辑原生字段、完全移除包装/WK 子树的候选 PID 39185 同样未收到输入：字段与提示可见，直接点击后 `n/e` 仍使 Finder 改选 `registration-before.txt`，未记录 native mouseDown/editing 回调。日志为 `find-focus-native-root.log`，构建为 `.build/preview-interface-focus-native-root-build.log`。所有临时探针已从正常源代码移除。

以上结果支持继续定位服务/宿主边界，尚不构成“所有系统版本均禁止输入”的结论。[MarkEdit 的公开改动 #1465](https://github.com/MarkEdit-app/MarkEdit/pull/1465) 曾在 navigation didFinish 同步设置 first responder，[后续问题 #1607](https://github.com/MarkEdit-app/MarkEdit/issues/1607) 又记录其 Finder 侧栏导航回归及系统版本差异；[markdown-preview #370](https://github.com/pluk-inc/markdown-preview/pull/370) 记录点击正文后标准全选/复制能工作。下一项候选只检验 didFinish 时机，不能把这些项目的结果冒充本项目验收。

### didFinish 时机与诊断结束

按 MarkEdit 原改动，在主壳 navigation didFinish 校验后、异步 render 前同步设置 WebKit responder 的候选 PID 40502 仍失败；点击查找后 `n/e` 仍切换 Finder 文件。日志为 `find-focus-shell-ready.log`，构建为 `.build/preview-interface-focus-shell-ready-build.log`。该自动聚焦随后移除，避免保留无效且可能影响 Finder 侧栏导航的行为。正常源保留严格校验的显式查找桥和内容无关 Debug 诊断；普通 Swift 构建及 65/65 renderer tests 通过。

当前 P0 **尚未确认修复**。服务窗口 firstResponder 与 DOM focus 不足以证明 Finder 已交出键盘，尚未识别受支持的宿主焦点请求方式；现有证据也不足以断言平台一律无法支持。继续实施独立的工具栏及 HTML 任务，不把它们或宿主测试写成 Finder 键盘验收通过。

诊断结束后已移除候选登记并恢复 `/Applications/Quicklook.app` 为该 bundle ID 唯一 preferred 登记（`registration-restored.txt`）；未替换安装文件或改其他 provider。所有临时原生探针、根视图属性覆盖和自动 makeKey/didFinish 聚焦均已移除。两页自建 Finder 标签页已关闭，原六页及 AppWink.app 原选中项已恢复。

最终原生清理已分别通过独立规格和质量复查：批准严格校验的显式查找桥、当前请求/代次保护与内容无关诊断，不代表原生 P0 修复通过。整窗关闭后的取消将在资源生命周期接入时补齐验证。

## A 单行工具栏

生产结构与生成资源已完成：文件名主体省略、扩展名保留，弱化元信息依次省略编码/计数/格式；右侧为模式、换行、查找静态图标，复制按钮及整篇 handler 已移除。模式名称、状态、完整悬浮说明和始终存在的辅助文本保留；MD 渲染态换行禁用，JSONL 记录/原文两态保留。

- 7 项新增行为回归先失败后通过；移除旧复制按钮测试后，当前 71/71 renderer/selection tests 通过。独立规格和质量审查均通过，内存重新生成的 HTML/CSS/JS 与提交工作区资源逐字节一致。
- 实际 WKWebView 12 项代表场景覆盖 420/520/920 CSS px、系统实际浅/深外观、普通/长文件名、MD 渲染/源码及查找展开，并补 JSON/JSONL/代码控件检查。工具栏实际高 44px、按钮 29×29px，同排无重叠、操作不越界、扩展名可见、无横向文档溢出。根代理独立查看 420 浅色、420 深色长名源码查找、920 深色长名及 920 浅色查找截图，未要求布局调整。
- 一项初始截图观察曾怀疑搜索行被滚动遮挡；同一不可变资源的自然对照在 snapshot 前、后及 +700ms 都测得 scrollY=0、搜索行 y=44–90，根代理所见最终截图也显示完整搜索行。没有通过修改生产样式或重置自然对照滚动来假称修复。
- 资源 renderer SHA-256：`2ff47910776d42d9b85da2e974f3191088abd8f27fd1a457f1377171b6b9dfd3`。证据：`.build/experiments/toolbar-layout/final-complete/{results.json,bundle-manifest.json,*.png}` 及 `final-search-natural-observation/`。这是布局/DOM 证据，不证明 Finder 实体键盘或新候选安装验收。

## 键盘证据边界与真人对照准备

最终独立审计指出，CUA `App.pressKey` 文档未规定是否激活目标 app、是否保留 Quick Look 的 key window。当前记录不能证明每个候选在硬件键盘下均失败，也不能据此宣布平台禁用键盘。仍须在实际加载本扩展的同一候选中完成一次真人按键对照，后续候选验收保持待办。

为此曾重登记最后构建的 didFinish 时机诊断产物（扩展二进制 SHA-256 `241b4f93f92bbfc06d70f52304b8068d827d18d16fc49c767f0a14dc348bf86f`），但 Finder 对旧样本及新的 `manual-focus-20261112.md` 均显示系统原生文本，未启动本扩展。因此未向用户提交该手动测试问题，未将系统界面当作本扩展证据。已恢复旧安装唯一登记（`registration-restored-after-manual-setup.txt`），关闭新增一页，原六页恢复。手动对照改在当前源的新候选构建及 provider 确认后进行。

## HTML 容器生产边界（Task 4）

已实现只依赖 Foundation 的有界准备状态、精确主壳/静态资源/当前 UUID 子文档路由、原生资源 token、弱回复握手和关闭/换文件失效。Markdown 图片生成当前 token URL，原生拒绝无 token 或旧 token 地址，读取/光栅化后再校验代次才返回数据。子 CSP 通过固定响应头交付；父策略保持脚本/样式 self，frame 只开放受控 document 路径。当前尚未启用用户 HTML 模式或类型声明。

- TDD：新增状态缺失先 red，5 项 UI 状态测试 green；Markdown token 实际 URL 回归先 red 后 green。npm build 与 72/72 JS tests、40 Core + 5 UI Swift tests、probe build 通过。
- `validate-core.py --include-preview-interactions`：60 loader 样本、19 既有 render 用例/145 断言及 19 容器交互检查通过。报告 `.build/validation/preview-container.json` 对应当前 probe SHA-256 `be4bbb21869313600f8835192a3e29ffab61506f2c2a5b02cc65c45fe56e13ea`，源码新旧检查无过期。
- 合成、独立的 WebKit 正对照实际请求 `/image` 一次且 naturalWidth=1；生产严格子策略的 loopback 计数为空。主壳真实握手、同源 DOM、Selection/Range/TreeWalker/滚动、CSS 隔离、旧地址/超限/子桥拒绝、整窗关闭后的拒绝均已测。子 page/defaultClient 的 click/keydown/copy 回调均为 0，child page 执行 WKError 4；这是已记录的平台约束，主 frame 原生命令的 DOM 替代路线已验证。
- 独立规格和质量复查均通过。以上不证明用户 HTML 清洗、惰性解析无请求、模式切换、生产键盘命令、Finder provider 或真人输入；它们仍属于后续任务。

当前源已构建并签名验证了 0.1.1（1201）候选，仅通过构建参数区分本轮诊断版本，源码版本未改。路径仍为已获准的 `.build/xcode-preview-interface-focus/Build/Products/Debug/OrbisPeek.app`。身份记录 `container-candidate-identity.json`；候选扩展 SHA-256 `5b1608c58e586f7b1dc390f663d7b736893ca6556274b0fcfba4819d26104e56`。已通过规格和质量审查，随后按既有授权临时登记用于真人键盘对照。

Task 4 质量复查补充证据边界：集成 probe 的“stale image”使用从未生效的 UUID；曾有效 token 在新目录替换后的撤销由直接状态测试覆盖，未宣称该单一 probe 已覆盖两种情形。

## 1201 候选：真人键盘对照待回复

两份同 ID 登记并存时 Finder 实际启动了旧安装 PID 49940；关闭该合成预览后，仅临时移除本项目旧 appex 登记并结束该进程，再登记候选。现已确认候选 PID 50045 的路径位于开发 app，AX 精确主壳与 `manual-current-1201.md · OrbisPeek` 匹配，新的单行三图标工具栏可见。

查找已展开，未再向候选发送自动按键；通过异步文本问题请用户亲手点击字段，测试 `ne`、中文、退格及 ⌘F。当前待回复，不能判定真人键盘通过或失败。截图/AX 为 `manual-1201-ready.png/txt`。此阶段候选是唯一临时登记，原安装文件未改动；对照结束后须恢复旧登记、关闭新增一页。开始本次对照时另观察到原应用程序页的 AppWink 快速查看已打开，恢复时保留该用户状态。Task 5 源码接入独立继续，不能覆盖当前 1201 产物。

## 隐藏/最小化生命周期补充（Task 5 跟进）

Task 4 审查后，独立、离屏且禁止激活的 AppKit harness 发现普通 `orderOut` 和最小化也会触发 `viewDidDisappear`，此时 `view.window` 仍挂接；重现/取消最小化会触发 `viewDidAppear`，没有新的 showFile。因此 1201 的无条件消失失效会令重现后的原生桥/资源不可用。证据为 `.build/experiments/preview-lifecycle/result.json`，这是新确认的问题，不当作 Finder 原 P0 的平台原因。

Task 5 正接入“消失即撤销、重现时按当前代次恢复同文件”的保守修正；显式关闭/新文件/失败必须清除恢复计划，旧回调不得覆盖新文件，不自动激活或抢焦点。若可在原受信主壳轻量保留模式/查询则保留，无法安全恢复时重载默认状态并说明范围。当前 1201 真人问题仍待回复，但答案只作为该诊断版本事实，不能代替这项生命周期修正后的最终验收。

1201 真人对照在收到答复前已宣布暂停：该产物含已确认的隐藏/最小化恢复缺陷，继续要求用户操作会混淆原始 P0 判断。此问题未作为任何真人键盘通过/失败证据；将恢复原登记和原预览状态，最终对照使用生命周期修正及类型接入后的候选。

## 1201 对照退出与锁屏阻塞

暂停通知后约两分钟，CUA 只读检查报告 Mac 已锁定且自动解锁失败，故无法取得手测后的 UI 状态，也没有继续发送界面操作。已通过异步问题请用户手动解锁，不索取密码；这不会暂停独立代码检查。

原登记已恢复为 `/Applications/Quicklook.app` 唯一 preferred（`registration-restored-after-1201.txt`），仅结束开发候选 PID 50045，未修改安装文件或其他 provider。1201 真人问题未收到答复，不存在硬件按键通过/失败结论。当前仍需解锁后关闭本轮新增一页 Finder 标签并恢复原 AppWink 快速查看；尚未谎称这部分 UI 恢复完成。最终手测使用修正后的候选。

## 静态 HTML 接入（Task 5 最终冻结）

用户 HTML 引擎已实现：无脚本受控子文档默认渲染、HTML 高亮原文切换、当前子正文查找/纯文本选区复制和原生菜单/快捷键适配；类型声明尚待 Task 6。所有文档模式 render 返回 Promise，等待当前视图完成/安全原文退回，文件与视图代次隔离旧结果。窗口内指令只进入受信主壳，查询编辑保留 WebKit 原生行为。

- 最终 98/98 JS、40 Core + 12 UI Swift tests、probe build、60 loader 样本、19 既有 render/145 断言及 112 交互检查通过，diff 检查通过。规格前端/原生两半及质量前端/原生两半均通过，发现的问题已逐项修正复查。
- 根属性/CSS：完整解析使用主 document.implementation 创建的独立 HTMLDocument（defaultView=null），重建仍在 template inert owner（defaultView=null）。这保留 html 的 class/style/lang/dir 和继承样式；允许 loopback/custom 图片及 inline-script 的独立正对照确实执行/请求，生产清洗解析/重建/序列化阶段无图片请求且文档脚本不执行。
- 当前可读范围：作者类名和 mark 不与内部装饰混淆；闭合 details 仅首个 summary 可查找/复制；打开后正文可读。body 上方 html 的隐藏/opacity/content-visibility 也检查，visibility:hidden 根下显式可见子节点仍可读。结构预算触及即安全退回有界原文，不静默丢内容。
- 代次/生命周期：旧 HTML A 的模式完成不能抢 B 的焦点；消失/最小化即时撤销，重现通过 epoch 票据恢复同文件新能力，不激活窗口或抢焦点。显式关闭、新文件和失败取消恢复。恢复为重新加载，模式/查询会重置，这是当前保守行为。
- 原生命令：公开 supplementalTarget 路由标准 nil-target Copy，查询继续使用继承的 WebKit Copy/SelectAll/Paste；直接 NSEvent 适配测试证明正文 ⌘A/C/F 各处理一次，包括 Caps Lock。查询 direct-super 离屏返回 handled 不代表实际键入，单独以标准编辑 action 验证结果。原生 marked-text 上下文无法在离屏建立，仅组合状态提示保护已测；不冒充真人 IME。
- 外链只在当前成功 render 票据有效时开放，失效/新加载/迟到旧完成不能授权旧主壳。固定主壳 URL 无法证明历史同 URL frame 的绝对身份，未超出实际状态门槛作声明。
- 剪贴板全部 item/type/Data 仅在进程内保存并精确恢复，未输出用户内容。标准菜单/正文快捷键适配已测；直接指定 WK 目标或 WebKit 内部右键菜单 Copy 未声称经过自定义纯文本提取。

最终冻结清单 `.build/validation/task5-frozen.json` SHA-256 `1322dfa6c8621469905567cc1797b503ef091df41a5e1e8f3bf2bbe3b58f21c3`；报告 `preview-html.json` SHA-256 `8593563d17c62e441abd40c30fcce9b5ce11d3ae655bb063eed1f815cfeb5b5a`。HTML 引擎用例仍显式 forced mode（类型未接入），真人键盘/IME/Finder、真实锚点点击与 sandbox 文件夹授权/撤销仍待最终候选验收。解析期独立零请求证明针对图片通道，未声称另做 CSS/font 的独立解析正对照。

## HTML 类型与配套工具（Task 6 完成）

当前清单加入 HTML / HTM / XHTML，实际 Foundation 路由分别为 `public.html` / `public.html` / `public.xhtml`。推导得到 230 后缀、87 格式组、56 文件名规则、195 UTI、86 个带后缀的组；plist 对本轮更名基线的变化仅为预览白名单增加两个精确 HTML 类型，没有改变 imported/exported 类型或默认打开关联。TXT、PDF、Office、CSV、SVG 及既有宽泛/冲突类型边界保留。

- 新旧工具栏判定兼容：当前图标界面不要求复制按钮，仍要求精确主壳、同一窗口/子树、对应文件标题和实际正文 marker；HTML 另要求受控子文档及渲染态证据。嵌套外部网页不能提供伪造的主壳标题或 marker。切换操作是否可用仍需真实 Finder 单独验收。
- registry Swift 5 项、Python Acceptance 50 项、生成文件检查、fixture 幂等和 62 个小样本结构检查通过。新覆盖语料仅写入 `.build/finder-coverage-preview-interface`，包含 230 项；这只是生成语料，没有执行新的全量 Finder 验收。
- 正常文件识别的 HTML / HTM / XHTML 和资源拒绝样例已加入默认渲染链。`preview-registry.json` 共 64 loader 样本、23 render / 186 断言、112 交互检查全部通过；原 19 个核心用例保留。Task 5 的强制引擎检查继续作为不同层级证据。
- 冻结 `.build/validation/task6-frozen.json` SHA-256 `8c495d0cd2cfd488c6694c6f5674a93f5aa0b9d134c8b99ea80bdf010bfa76ec`；`preview-registry.json` SHA-256 `7c8a2021c807391e5bfbe156abbc264d1deda9a484daf28aa79ec08807b97892`。根代理逐文件复核 20 项 hash 一致，并确认四份历史报告无 git diff。旧系统 HTML 样本字节保留，当前 manifest 已改为 HTML 模式并说明其历史文案。

最终跨模块复查另发现静态 HTML 选区复制对 CSS `white-space` 的处理不足：`pre-line` 的可见换行被折叠，`pre` 后代显式 `normal` 又无法覆盖保留状态。当前已安排聚焦修正及真实 WK 回归；上述 Task 5 / Task 6 冻结报告保持原样，不将它们改写成修正后的证据。跨 inline 文本节点的查找限制为原有行为，本轮未据此扩展搜索算法范围。

Task 6 已分别通过独立规格与质量评审；两者逐项核对冻结 hash，未提出待修问题。当前阶段未执行新的登记、Finder 操作或全量后缀验收。

## 最终复制空白回归与自动检查

最终跨模块复查先发现 `pre-line` 换行和 PRE 后代覆盖问题，再在复查中补出跨 inline 文本节点的行边空白。两轮均先有真实 Range 失败回归，再修正并以实际 WebKit 排版验证；最后独立复审通过。

- 当前复制按 computed `white-space` 处理，`pre-line` 保留换行并折叠横向空白，`normal/nowrap` 可覆盖 PRE；`pre-wrap/break-spaces` 继续保留空白。跨节点修正仅处理同一 block/cell 内相邻的已选折叠空白，保留显式 BR、保留空白模式及选区边界。
- 实际双文本节点样例同时测得行边空白宽 0、下一行 y 差 30、x 偏移 0；整选为 `AA\nCC`，部分选区为 `A\nC`。未选中换行时仍保留选区内的 `AA ` / ` CC`，没有用整段文本替代部分选区。源文空行、缩进、真实 U+200B 与大整数的既有检查保持通过。
- 最终 106 JS、41 Core + 12 UI Swift、50 Python Acceptance，以及 64 loader 样本、23 render / 186 断言、156 交互检查均通过。根代理另跑 `./scripts/test` 和完整 Python 检查通过，日志为 `preview-interface/final-boundary-tests.log` 与 `final-acceptance.log`。
- 最终冻结 `.build/validation/task5-whitespace-boundary-frozen.json` SHA-256 `ce23c0f99de19f606881f472c0be1be51cc070c7df761f6aa6beb02e8e8e7daf`；报告 `preview-final-whitespace-boundary.json` SHA-256 `d3ce3253af99c36335ab972b632205445552221dbd2535aa5748ec23cc8dabbe`，根代理复核全部当前文件和 artifact hash 一致。`preview-interface/core-results.json` 是该报告的逐字节归档副本，不是另一次执行。
- 之前的 Task 5 / Task 6 / 首轮空白修正报告、冻结清单与原始证据保留；Task 6 的 `validate-core.py` 在后两轮仅增加明确的 probe 检查，其余受保护文件保持一致。WebKit native Selection 对 `pre-line` 行边可能含不绘制的空格，未将其原始字符串等同于可见排版；新增检查分别核对几何与自定义复制结果。

以上仍不证明实体键盘、中文 IME、真实 Finder provider、实际拖选粘贴或最终候选沙盒授权/撤销通过。

## 最终 1202 开发候选

已用现有 Developer ID / Team 配置构建 0.1.1（1202），启用既有 App Group 目录能力，源码版本不变。候选为 `.build/xcode-preview-interface-focus/Build/Products/Debug/OrbisPeek.app`，构建命令使用 `--directory-access --no-register`；没有替换安装、创建证书/profile、扩大目录授权、公证或发布。

- Xcode build 成功，宿主及扩展 `codesign --verify --deep --strict` 通过，sandbox 与既有 App Group entitlement 正确。
- 宿主/扩展各三份 HTML/CSS/JS 资源均与当前生成文件逐字节一致；扩展内 195 项预览声明与当前生成 plist 完全一致。
- 扩展二进制 SHA-256 `b697b8220a3d78429065b751ef3884a9f627ed0c862b95bf3b0f8d0cd953ec02`；renderer SHA-256 `372a945bd2c9f35e85bddfbf38885722940a1f8c42e0cf26b06e8570125482e9`。`candidate-1202-identity.json` SHA-256 `71aeae4d481eb2714a2ce55106c38c3c039c535b016a8d57a639f57c60afaa34`。
- 构建结束移除候选临时登记后，精确 bundle ID 查询仍只有原 `/Applications/Quicklook.app` 一项 preferred（UUID `025B5BA9-28EF-4A16-BD08-18B9344AC996`）；原安装主二进制 SHA-256 仍为 `a0f020337f8dfb53327c6321a5a025c1ed40cbbbd37c45030b93dde8d61556cb`。证据 `registration-after-1202-build.txt`。
- 根代理查看 `preview-interface/final-html-1202.png`：当前正常识别的 HTML 显示受控正文和内嵌样式，920 CSS px 工具栏保持单行，无复制按钮，模式/换行/查找图标完整；缺失图片的合成样例明确显示资源提示。这是当前源的离屏 WK 结果，不是 Finder 截图。

1202 尚未临时登记执行最终 Finder 验收。Mac 解锁问题未收到答复；最终候选的实体输入、IME、拖选粘贴、HTML provider、沙盒图片授权/撤销、实际锚点点击均保留未验证。1201 阶段的一页测试标签与原 AppWink 快速查看恢复同样待解锁，未宣称 GUI 已全部恢复。

## 1202 最终布局复查发现的 HTML 画布问题

隔离 harness 使用 1202 不可变对象与实际资源，校验 420/520/920 × 深浅色 × HTML 渲染/原文共 12 项，276 项布局断言通过。首次 requested width 被 AppKit preferredContentSize 覆盖的运行保留为 preliminary；权威运行显式调整仅测试窗口，并核对实际 viewport。证据为 `.build/experiments/final-html-layout/{results.json,REPORT.md,final-host-sizing/}`。

根代理查看深色渲染截图确认正文可读性缺陷：作者根颜色 `rgb(18,52,86)` 保留，但默认注入 `color-scheme:light dark`，html/body 又无自己的背景，导致应用深色 `rgb(30,32,36)` 透出，形成难读的深色文字。布局几何通过不能掩盖这项实际视觉失败，1202 不作为最终交付候选。

聚焦修正采用浏览器式文档画布：HTML 默认使用浅色 Canvas / CanvasText，作者后续或 inline 的颜色、背景与明确的 color-scheme 可覆盖；工具栏、查找与原文继续跟随系统。该选择优先保留作者配色和自然文档背景，避免自动给所有网页启用暗色画布；不引入颜色猜测或重写作者 CSS。最终候选改为 1203，待新检查与独立复查后构建。

420 px 下作者 pre 有 468 px 的子文档横向内容，但被 iframe 包含，没有扩大父文档宽度；父文档存在正常纵向滚动。这些均按实际值记录，没有声称所有文档零溢出或任意作者配色都通过对比度检查。

## HTML 画布修正最终冻结

已将三个画布默认值放入首个匿名 cascade layer，并以 `:where(html)` 保持零选择器权重；其他既有字体、图片与查找标记样式不改。作者 inline、html、:root、通用选择器及命名 layer 的颜色 / 背景 / color-scheme 均可覆盖默认值。该修正分别通过独立规格与质量复查。

- 实际深浅宿主中，默认画布均为不透明白色、默认文字黑色；作者海军蓝根颜色、body 的自定义前背景、根 19px 字体与 class 继承保留。明确的作者 dark scheme 呈现暗色 Canvas / 白字，命名 theme layer 的 `rgb(8,9,10)` 背景与 `rgb(230,231,232)` 前景也在两个宿主中保留。
- child 的 `matchMedia(prefers-color-scheme)` 可继续反映宿主外观，因此检查同时记录 root used color-scheme 与实际 Canvas 颜色，没有用媒体查询值冒充画布配色。工具栏及原文的实际宿主配色保持通过。
- 最终 110 JS、41 Core + 12 UI Swift、64 loader、23 render / 186 断言、212 交互检查通过；根代理再次运行 `./scripts/test` 通过，日志 `preview-interface/final-canvas-tests.log`。此前完整 Python Acceptance 的 50 项对应输入未变，仍保留原日志和 hash，不覆盖阶段证据。
- 冻结 `.build/validation/task5-html-canvas-frozen.json` SHA-256 `aa197dfaf22714b8350913e09417e8541c7aab2cc2c2238ddedd5ba912fd2e76`；报告 `preview-final-html-canvas.json` SHA-256 `6e7f9a54fb73b73bc06f7d161f8a06a3a52581f5c12757f905bb9a627afe23dd`。根代理及两名独立审查者均核对列明的当前 / 历史文件与报告 hash。`preview-interface/core-results-1203.json` 为本报告逐字节归档，先前 1202 的 `core-results.json` 与所有已列入冻结清单的证据保持原样。

该修正不声称任意作者自行指定的前背景组合都满足对比度，也不重新配色作者 CSS。无配色声明的 HTML 使用浏览器式浅色文档画布；文档可通过自己的 CSS 选择其他配色。最终 1203 及其实际布局核对在下一段单列。

## 最终 1203 候选与交付边界

1203 已在同一个获准开发路径构建成功：`.build/xcode-preview-interface-focus/Build/Products/Debug/OrbisPeek.app`。宿主和扩展的 deep/strict 签名验证、既有 sandbox/App Group 配置、195 项类型声明，以及两套各三份生成网页资源的逐字节核对均通过。源码版本保持 0.1.1（12），仅本轮构建号参数为 1203。

- 身份清单 `preview-interface/candidate-1203-identity.json` SHA-256 `7ee9395ee863c59f2bea87bc02fdec806069184e3689ccf44764d69e52681bfc`；扩展二进制 SHA-256 `15e0d36085518f6ed982788ad0ef64007ce04bc833383b0c34eb7f3406e5f226`；renderer SHA-256 `43534061e0e1648ce247053013b15cd416d55a61d9231fa78756e9a7cfaade6b`。
- 最终仅一轮有界布局复核使用实际 1203 对象和资源，12/12 项、336/336 断言通过：420/520/920 CSS px、浅深色、HTML 渲染/原文及代表性查找展开。根代理独立查看 920 深色渲染、420 浅色渲染及 420 深色原文截图，确认正文可读、单行工具栏、扩展名与图标清晰。证据 `.build/experiments/final-html-layout-1203/{results.json,REPORT.md,final-host-sizing/}`。
- 子文档现在是不透明白色 Canvas，作者海军蓝保留；作者明确指定其他配色的控制样例通过。宿主工具栏和原文的深色保持。父文档无横向扩大；作者 pre 在 420px 下有被 iframe 包含的横向内容，正常纵向滚动保留。未把“所有内容零溢出”当通过条件。
- 该复核未修改生产、候选、对象或资源，86 份已核对的 1202 原证据也保持 hash。原安装仍为 0.1.1（12），主二进制 hash 未变；构建后的精确登记查询仍只有原安装 preferred，候选没有留在登记中（`registration-after-1203-build.txt`）。

README / 中文 README、欢迎页、当前验证方案和发布验收说明已经同步；新覆盖生成命令使用单独目录，四份历史验收报告仍无 git diff。没有创建分支、提交、推送、PR 或发布包。

**当前不能宣称整轮 Finder 验收完成或查找输入 bug 已修复。** 仍需 Mac 解锁后：恢复 1201 留下的自建标签与原预览状态；按既有临时登记授权使用 1203 确认实际 provider；用实体键盘验证查找、中文 IME、查询编辑和快捷键；真实拖选粘贴核对；HTML/HTM/XHTML 模式切换、沙盒图片授权/撤销与实际链接行为。自动 DOM、离屏 WebKit、签名与构建结果不能替代这些项目。解锁问题仍待用户答复，未重复索取登记许可。

## 用户授权替换安装后的校验（2026-11-12 晚间）

用户随后明确要求“替换安装并进行校验”，因此此前“不替换安装”的范围已被本次指令更新。已于本地 20:43 将 1203 安装到 `/Applications/OrbisPeek.app`，原 `/Applications/Quicklook.app` 移到可恢复废纸篓副本，同时保存压缩备份：`~/Library/Application Support/OrbisPeek/Backups/20261112-204337/Quicklook-0.1.1-build12.zip`。压缩包 CRC 及两份旧二进制字节核对通过，未清空废纸篓。只结束原安装的旧 extension PID 82175；未结束 Finder、重置 Quick Look 全局状态或改变其他 provider。

- 新宿主 / 扩展二进制与 1203 冻结候选一致，deep/strict 签名和六份网页资源核对通过。development 安装检查通过；Debug/arm64 的既有发布限制按原样记录，不假称 Universal Release 或公证。
- 当前精确 bundle ID 登记只有新安装一项且为 `+`，195 项白名单与注册表完全一致，含精确 HTML/XHTML 类型而不增加宽泛兜底。宿主没有新增文档打开 handler。
- 同七份真实合成文件的 NSWorkspace 默认打开应用在安装前后完全相同：MD Typora、JSON/TXT CotEditor、HTML/HTM Chrome、XHTML Safari、JS 微信开发者工具。PDF/Office 无本批实际样例，未声称它们的实际默认程序已单独核对。
- 新宿主“预览示例”实际收到 JSON 扩展回执：`0.1.1 (1203)`、`/Applications/OrbisPeek.app/Contents/PlugIns/QuicklookPreview.appex`，request/receipt ID `E6667718-A6E7-4CB9-A401-E5D9128EF70D` 一致、age 0。宿主沙盒中的插件发现查询仍为 unavailable，未用它否定外部登记和真实回执。
- Finder Space 的 Markdown 对照实际显示精确 `quicklook-app://bundle/index.html`、`final-1203.md · OrbisPeek` 与正文，原文 / 渲染往返通过，单行工具栏和独立查找图标可见。查找展开后已经请用户亲手键入英文 / 中文、退格与 ⌘F；当前待回复，未使用自动按键结果替代实体输入结论。
- **本轮发现实际 HTML 路由未通过**：三份 HTML/HTM/XHTML 均显示系统 `file://` HTML 预览，没有 OrbisPeek 外壳和模式图标。磁盘 plist、PlugInKit cached bundleInfo、精确 UTType 和启用登记均正确；不能把宿主或离屏成功改写为 Finder HTML 通过。已准备全新文件名 HTML 对照，待当前手测结束后继续。现有证据不足以归因全局缓存或宣布平台一律不支持，未采取全局 reset、Finder kill、宽泛类型或打开关联改动。

本轮旧测试标签页已先关闭，原六页和 AppWink 选中项保留；根据新任务另开一页 `candidate-1203-fixtures` 用于验收，目前留有等待用户实体输入的预览。当前没有重新打开原先已被用户关闭的 AppWink 预览。所有实际安装证据位于 `.build/validation/preview-interface/installed-1203*`、`install-1203*`，与上午冻结报告分开保存。

## 安装后验收结论（已完成本轮操作）

用户对 1203 的实体键盘问题答复为“仍触发 Finder 定位或无法输入”。这使查找项从“待确认”更新为 **已验证失败，尚未修复**。测试前已确认实际 Markdown 主壳与新安装进程路径；准备查找后没有再发送 CUA 按键，用户手动操作期间也未干预 UI。其后 Finder 显示已选择同一合成目录的 `manual-fixtures.json`，与用户报告一致；未把它归咎于自动按键工具。

全新 `installed-1203-fresh.html` 也实际显示 `file://` HTML 页面、原生 Chrome 打开按钮和合成正文，没有本扩展主壳或模式图标，因此 **HTML 路由项已验证失败**，不只是旧文件预览缓存。三种后缀及新文件名的 AX 证据分开保存。当前未进一步重登记、重置缓存、重启 Finder 或修改类型关联来掩盖失败；新安装与有效登记保持。

已完成：安装 / 签名 / 195 项精确声明 / 六份资源 / 唯一启用插件 / 七种默认打开应用保留 / JSON 扩展回执 / Finder Markdown 默认与原文往返。未通过：实体 Finder 查找输入、本扩展的 HTML/HTM/XHTML Finder 接管。实际 Finder 选区复制、完整 IME / 快捷键及本轮沙盒授权撤销仍未验证，未计入通过。

只读原生路径复查未发现可直接验证的新公开 Quick Look 焦点交接开关。系统的“views or subviews claim first responder”警告是附加证据，不构成所有平台绝对不支持的结论；未重新引入已知会争夺 Finder 焦点的自动 didFinish 聚焦。此前根原生字段实验仅使用 CUA，如后续需要区分宿主 / WebKit，应作为单独实体对照，不作为现已修复的依据。

本轮新建的测试预览和标签页已经关闭，原六页与 AppWink 当前选中项恢复，没有强制重新打开此前已关闭的原 AppWink 预览。CUA 最终结果已确认并提交完成摘要。新版保留在 `/Applications/OrbisPeek.app`，旧版压缩备份及废纸篓恢复副本保留。没有分支、提交、推送或 PR。

## 继续修复：纯原生输入对照与宿主正对照

按用户继续修复两项的指令，使用隔离 Xcode 工程构建 1204 对照：主控制器直接继承 NSViewController、仅标准 NSTextField，编译符号/依赖证实扩展不链接 WebKit 或 QuicklookUI；无 makeKey、强制 firstResponder、事件监听或自定义文本框覆盖。230 份生产文件及安装 1203 / 原候选树逐字节未变，身份与冻结清单位于 `.build/experiments/native-input-control/`。

Finder 确认唯一标记 `NATIVE INPUT CONTROL 1204` 后没有发送自动按键。用户实体结果为“中文输入法输入ne后，按空格时预览窗口关闭了”；随后 AX 显示 QL 关闭、ne-sentinel.md 被选中。这将失败范围缩小到该 Finder/扩展宿主上下文的输入交接，而非仅网页事件；不据此宣称所有 macOS/Quick Look 平台永远不支持文本输入。已恢复 1203 的唯一启用登记，对照未替换 `/Applications` 文件，关闭自建页并尊重用户期间更改后的五页/resume 状态，未恢复成过期的六页布局。

HTML 采用公开 `qlmanage -p -o` 的无界面四格请求类型对照，保持真实文件字节和路径不变。普通 HTML 返回原始 URL，其余无产物；已知 Finder 成功的普通 Markdown 同样无产物，故该 CLI 实验对现代 view-based appex 分发不具区分力。所有输出/日志保存在 `.build/experiments/html-routing-request-crossover-1203/`，明确记为 inconclusive，未当作修复或不可实现证明。

当代现代 QLCodePreview [完整提供器](https://github.com/Konstruukt-Labs/qlcodepreview/blob/aebb00e65c05698e8b65657ffc7f362d76b61c15/QLCodePreview/QLCodePreviewProvider.m#L24-L87)和[HTML 专项限制说明](https://github.com/Konstruukt-Labs/qlcodepreview/blob/aebb00e65c05698e8b65657ffc7f362d76b61c15/README.md#L138-L156)提供相同原生 HTML 路径的维护者经验，不等于 Apple 跨系统保证；未采纳其对所有 public UTI 的宽泛表述，因为本项目 JSON 已实际通过。旧 QLHTML 是 legacy CFPlugIn，Apple [macOS 15 说明](https://developer.apple.com/documentation/macos-release-notes/macos-15-release-notes#Quick-Look)已移除该受支持路径。没有找到可据以修改优先级的公开控制入口，未改用户类型归属/默认应用或系统组件。

进一步用当前安装宿主、同一 HTML 做正对照：真实 `quicklook-app` 主壳和受控子文档可见，⌘F 实际聚焦输入框；逐键 n/e/e/d/l/e 后值为 needle、匹配 1/1，退格得到 needl，e+空格得到 `needle ` 且窗口不关闭，渲染/原文往返保留查询。证据 `native-input-control/host-html-positive-ax.txt/png`。这证明宿主交互路线可行，仍不算 Finder 输入/接管通过或实体 IME 完整验收。

现已向用户提出明确的架构范围选择：按需独立阅读窗口，Finder 查找按钮转入、HTML 通过打开方式进入；Finder Space 保留系统原行为，不加常驻 helper/全局监听/默认应用改动。该选择会改变原先 Finder 原位交互要求，所以在生产实现前等待用户答复。当前安装仍为 1203；没有以 1204 诊断版冒充修复安装。

## 已接受的独立阅读窗口实现

用户随后明确答复“采用独立预览窗口”。以 [已确认设计](superpowers/specs/2026-11-12-reader-window-handoff.md)为本轮验收范围：Finder 放大镜转入带查找的独立窗口；HTML / HTM / XHTML 使用“打开方式 → OrbisPeek”；保留原 Space 行为和默认打开应用。历史 Finder 原位输入及 HTML Space 路由失败结论保留，不将新入口的成功写成旧入口已修复。

实现使用现有 App Group 的有界一次性隐式 bookmark 请求，显式定位当前扩展所属 app；独立窗口持有自己的加载、预览和访问 scope。窗口未成为 key 或请求已失效时不自动聚焦，不增加全局输入监听或常驻 helper。1205 安装前已另存七份原样例的实际默认应用快照，当前正式安装及唯一登记仍为 1203。构建、备份、替换和实际新入口结果将在下文单独记录。

### 1205 安装与首次实际入口检查

独立规格 / 质量检查通过后，以现有 Developer ID / App Group 构建 1205。安装前校验先拦截了 XcodeGen 丢失宿主文档声明的问题，已将精确 HTML/XHTML Alternate 与内部请求声明补到 `project.yml`，并增加实际临时 XcodeGen 回归；随后深层签名检查发现增量构建的嵌套资源签名失配，采用干净重建通过。两次未通过的候选均未安装。

最终候选 24 份冻结文件、195 项扩展类型及六份网页资源核对通过，自动检查为 JS 113 / Swift 66 / Python 52、实际 WebKit 64 loader / 23 render / 186 断言 / 212 交互、13 项 reader 生命周期检查。根代理独立 `scripts/test` 通过。实际替换为 `/Applications/OrbisPeek.app` 1205 后，完整 59 份文件 hash 与候选一致，deep/strict 签名、development 安装检查和唯一启用登记通过。同七份样例的实际默认打开应用与安装前完全一致。

1203 压缩备份位于 `~/Library/Application Support/OrbisPeek/Backups/20261112-224217/OrbisPeek-0.1.1-build1203.zip`，CRC 和两份旧二进制核对通过，原 bundle 保留在 `~/.Trash/OrbisPeek-0.1.1-build1203-20261112-224217.app`。只结束两份已确认的自有旧宿主进程；未结束 Finder 或重置全局缓存。

**真实新入口首次检查未通过，继续修复。** Finder Markdown 主壳、单行工具栏和“在窗口中查找”图标显示正确；点击后显示无法打开窗口的错误，App Group 下没有生成请求目录。首次自动点击超时后 extension 已退出，但没有 crash report，不能仅凭退出认定崩溃；第二次仅点击能稳定得到错误。HTML 的正常“打开方式 → OrbisPeek”已经列出且默认仍为 Chrome，点击后仅出现宿主主页，无阅读窗口或错误提示。将补充精确阶段日志并修正原生文件打开事件接收，再以新构建继续验收；这两项尚不计入通过。

### 1206 实际结果与用户取消查找

内核日志确认当前 Quick Look 进程在创建 App Group `reader-requests-v1` 时收到 `file-write-create` 拒绝，证据 `preview-interface/installed-1205-sandbox.log`。既有诊断机制也已记录该扩展上下文的共享写限制，未据此扩充 entitlement 或申请权限例外。1206 改为标准文档 URL + 签名扩展静态标记的批次，并通过原生 AppKit 文件打开 delegate 接收；原请求文件 / 内部 UTI 移除。独立规格和质量审查通过，Swift 63、Python 52、7 项生成 / 资源检查、13 项离屏 reader 检查通过。

1206 签名候选已安装，60 份文件 hash 与候选一致、deep/strict 签名及唯一启用登记通过。Finder 放大镜仍显示交接错误，精确日志为 `readerHandoff stage=launch domain=NSCocoaErrorDomain code=256`；未将其算作成功，亦未推断所有公开文件打开方式均不可用。

随后通过正常 Finder“打开方式 → OrbisPeek”选项并按 Return 执行，确认新宿主 PID 31849 已由该动作启动，再绑定 CUA app。实际窗口为 `reader-entry-1206.html · OrbisPeek`，主壳与受控 HTML 子文档均正确，默认显示实际正文，主页隐藏。证据 `preview-interface/installed-1206-html-cold.txt/png`。此前 1205 的菜单尝试未能确认文件打开事件已经送达，不把“仅见主页”单独当作旧事件 API 不支持的证明；1206 原生接收路径的实际通过另行记录。

用户最新指令为“先不做查找功能了，按没有查找功能的状态首尾吧”。因此停止查找输入与跨进程交接调试，以 [无查找最终范围](superpowers/specs/2026-11-12-preview-without-find.md)收尾：移除查找界面、快捷键及专用交接，保留复制、紧凑信息、模式 / 换行，以及已可用的 HTML 打开方式独立窗口。旧失败记录保留，查找不再是待完成验收，也不写成查找 bug 已修复。

1206 压缩备份已保存于 `~/Library/Application Support/OrbisPeek/Backups/20261112-231249/OrbisPeek-0.1.1-build1206.zip`，CRC 与两份二进制核对通过；1207 安装前实际默认应用快照已保存。最终构建与验收结果将单列。

## 最终交付：无查找版本 1207

已按用户最终范围完成并安装 `/Applications/OrbisPeek.app` 0.1.1（1207）。查找按钮、输入栏、快捷键 / 原生命令入口、焦点及 reader 交接 bridge、静态标记与专用状态均已移除。工具栏保留模式与换行图标，文件名后的辅助信息仍为紧凑单行，仍无复制按钮。正常 AppKit 文件打开接收和独立阅读窗口保留。

- 独立规格及质量复查通过。最终自动检查：92 JS、41 Core + 16 UI Swift、53 Python；230 后缀 / 87 组生成检查，App DEBUG 类型检查，9 项无查找原生检查；实际 WebKit 64 loader / 23 render / 186 断言 / 212 交互检查通过。当前交互检查已适配为无查找断言，同时保留复制、CSP、资源和生命周期边界。覆盖报告器新增无查找工具栏 profile，兼容历史证据，未改写旧 227 报告。
- 最终冻结 `.build/validation/no-find-1207-frozen.json` SHA-256 `b5f8bfe63672422c0eb03b5ccab212714063cc3cbc0e60fb000f22ec57408fab`。根代理最终核对 30 份源码 / 测试 / helper hash 全部匹配。probe 的 mtime 保守标记仅因控制器 EOF 空行清理而保留；其已通过的函数行为未变。正式 app 已在该清理后的 v3 源码上重新编译并签名，没有伪造时间戳。
- 安装后完整 59 份文件 hash 与候选逐一一致；主 / 扩展 deep/strict 签名、六份网页资源、195 项精确扩展类型、宿主仅 HTML/XHTML Viewer + Alternate、已移除标记和内部请求 UTI 均核对通过。首次异步登记查询曾无结果，随后仅重登记精确安装 app/appex；最终唯一启用项为 `/Applications/OrbisPeek.app/Contents/PlugIns/QuicklookPreview.appex`，development 安装必需检查全部通过。
- 七份原样例在安装前、安装后及 UI 操作后的实际默认打开应用一致：Markdown Typora、JSON/TXT CotEditor、HTML/HTM Chrome、XHTML Safari、JS 微信开发者工具。1206 原 bundle 留在 `~/.Trash/OrbisPeek-0.1.1-build1206-20261112-231249.app`，压缩备份及更早备份保留。没有 Finder kill、全局缓存重置、其他 provider 调整或默认关联设置。

实际界面通过项：

| 场景 | 结果 |
|---|---|
| HTML 冷启动打开方式 | Finder 正常“打开方式 → OrbisPeek”启动安装路径 PID 37328，随后才绑定 CUA app；独立窗口的精确主壳、受控子文档和正文正确，默认渲染 |
| HTM / XHTML 热启动 | 同一运行宿主分别打开对应独立窗口，三个后缀均能渲染 / 原文往返 |
| 无查找及紧凑布局 | 三种 HTML、Finder Markdown / JSON 均仅有适用的模式 / 换行图标，无查找栏或复制按钮；阅读器 ⌘F 未展开查找。实际查看原文截图，文件名、同行信息、两个图标和正文清晰，无原设置侧栏挤压 |
| HTML 换行 | 原文下可关闭再启用换行，渲染下对应按钮禁用，返回默认渲染正常 |
| 实际复制 | 中文选区、整个渲染正文及高亮原文分别复制到新建普通 TextEdit 文稿；渲染结果无工具栏 / metadata，原文无行号。证据保存为 `installed-1207-copy-verification.rtf`，文稿随后关闭 |
| Finder Markdown | 宿主退出后，精确本扩展主壳和正文可见，默认渲染 / 原文往返通过，无查找入口 |
| Finder JSON | 格式化正文包含当前 build / 中文 / 数组，原文切换准确，无查找入口 |
| 设置入口及关闭 | “安装与自检”可重开主页，关闭主页后既有阅读器仍可见；最后阅读器关闭后 CUA 报告 app 退出，未留测试窗口 |

复制验收的实际剪贴板目标为独立阅读窗口。Finder 远程正文的 AX 双击尝试曾关闭 Quick Look，未据此判定复制 bug，也未将其记作 Finder 实体选区复制通过；实体 Finder 复制留作单独复测。系统文件对话框的路径字段连已知粘贴正对照也未响应，因此未拿该字段的无变化判定产品复制失败，最终使用普通 TextEdit 完成复制核对。查找已取消，不再进行查询输入 / IME 验收；HTML Space 的原生路由结论保持，新的成功入口明确为打开方式。

所有自建预览 / 阅读窗口和 Finder 测试标签已关闭，原五个标签页及 resume 当前位置恢复。TextEdit 临时文稿保存在受控证据目录后关闭，原打开面板返回 build12 位置；没有修改用户文稿。CUA 完成摘要已提交。最终实际摘要为 `.build/validation/preview-interface/installed-1207-acceptance-summary.json`，包含源码 / 安装 / 默认应用及证据 hash；`git diff --check` 通过。没有创建分支、提交、推送或 PR。

本次为 Debug arm64 开发安装，保留安装验证器既有的发布 / 公证未知项；没有借此宣称 Universal Release、跨系统或全格式重新验收。PDF / Office 无本批实际样例，未单独声称其默认应用通过。

## 2026-11-14 Finder 选区复制复测

按用户要求对 1207 的 Finder 预览单独复测，已将此前“Finder 实体选区复制未单独验收”更新为：**渲染和原文模式下的选区 ⌘C 均实测失败，触发扩展崩溃。** 两个独立文件请求均先观察实际鼠标选区，再执行复制；对应崩溃 PID 为 38739 与 63048，重复的 Copy responder 调用链导致栈耗尽。不能用此前独立阅读窗口的通过结果替代。

详情见 [本次复制复测](finder-copy-validation-2026-11-14.md)，当前功能统一列于 [功能清单](app-features-2026-11-14.md)。本次只校验和记录，59 份安装文件保持不变；没有重装、修改登记或重置 provider。自建预览、剪贴板窗口及 Finder 窗口已关闭，恢复校验前桌面状态。

## 2026-11-14 复制修复与工具栏定稿（1208）

后续已修复公共 Copy 命令回流，并重新安装 0.1.1（1208）。实际 Finder Markdown 渲染和跨行原文选区均经 ⌘C、系统“文本”剪贴板视图及 TextEdit 粘贴保存核对通过；原文保留空行和标记、不夹带行号，同一扩展 PID 72485 持续存活。内部重复文件名已隐藏，外层标题及内部元信息 / 模式 / 换行图标保留，查找继续移除。

93 项 JavaScript、62 项 Swift、相关 35 项 Python 和 19 项实际 WebKit Copy probe 检查通过；签名、完整安装文件、唯一登记及七份原样例默认打开应用核对通过。自建测试标签和粘贴文稿已关闭，原 README.zh-CN.md 渲染预览已恢复。当前结论及本轮证据边界见 [1208 修复验收](finder-copy-repair-2026-11-14.md)，此前 1207 的失败记录保留。
