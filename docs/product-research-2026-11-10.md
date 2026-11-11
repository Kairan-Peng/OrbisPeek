# macOS 多格式 Quick Look 插件：产品调研

调研日期：2026-11-10。目标：开源、轻量，通过 Finder 的 Space 快速预览尽可能多的文本文档，并保留 PDF / Office 等常用文档的预览体验。

本报告区分三类信息：**已核验事实**来自官方文档、项目 README、许可证或源码；**产品建议**是据此提出的判断；**待验证项**需要构建、真实文件与多版本 macOS 实测。本轮未安装竞品、未构建原型、未测试渲染效果或性能。

## 1. 结论与建议

建议做一个“**补齐 macOS 文本与开发文档预览的开源工具**”：统一 Markdown、JSON/JSONL、配置文件与源码的阅读体验，PDF / Word / Excel / PowerPoint 由系统继续处理。

主要判断：

1. **值得做，但“把多个插件装进一个包”不足以形成差异。**已有 Glance、FreeLook、Pique，以及商业综合工具。价值应落在稳定的类型覆盖、好读的渲染、中文编码、大文件降级、安装诊断与持续维护上。
2. **优先复用模块与格式适配经验，谨慎完整 fork。**Glance 的维护分支仍有更新，但其 Web 渲染层仍使用旧 `WebView`；FreeLook 使用 `WKWebView`，更接近文本优先的路线，但项目较新，实际成熟度需要验证。
3. **PDF / Office 首版沿用系统。**Apple 已提供这些文档的预览。重新打包办公引擎会扩大分发、资源与维护成本，且不能保证解决所有兼容性问题。[A1][A2]
4. **“渲染器支持”与“Finder 能调用”必须分开。**UTType、其他软件的文件关联、系统 provider 都会影响结果。不能只按高亮库的语言数宣称支持数百种文件。[A3][F2]
5. **先验证最难的边界，再确定基座和范围。**优先做类型路由、本地图片、编码、大 JSONL、插件共存的 PoC；不宜先承诺“所有文本”“所有 HTML 页面”“Office 完全保真”。

推荐路线：以 Swift 原生宿主 + 现代 Quick Look Preview Extension 为基础，优先评估 FreeLook 的文本外壳及 Glance 的格式分层，统一渲染与降级策略。若决定直接大量采用 sbarex 系列代码，可选择遵循其 GPL 许可要求的开源发行路线；不必因为它是 GPL 就排除优秀实现。

建议 MVP 暂以 **macOS 15+** 为支持基线；这属于降低兼容与测试成本的产品选择，不是现代扩展 API 的最低系统要求。

## 2. 用户与产品机会

### 2.1 首批用户假设

| 用户 | 高频文件 | 想完成的动作 | 影响体验的细节 |
|---|---|---|---|
| 开发者 | README、源码、配置、diff、日志 | 确认文件内容，复制一段，再继续操作 | 高亮、换行、行号、复制、打开速度 |
| 数据 / AI 工作流用户 | JSON、JSONL、CSV、Markdown | 看样本结构、坏行、长记录、生成的文档 | 大文件有限预览、格式化、表格、Markdown 图表 |
| 运维 / Mac 管理员 | YAML、TOML、properties、plist、shell | 快速检查配置和值 | 注释保留、编码、键值易读、未知扩展名 |
| 普通办公用户 | PDF、Word、Excel、PPT、TXT、HTML | 不打开完整应用就确认文件 | 原生预览稳定、安装简单、不破坏原有体验 |

这些是产品假设，不是已经完成的用户访谈结论。本轮没有获得可靠的装机量、活跃用户或市场规模数据。

### 2.2 有依据的机会

- **整合需求已被验证为一个产品方向。**Glance 本身就以综合预览定位，覆盖源码、Markdown、压缩包、Notebook、TSV；Unfold 也提供多类文件预览。[C1][C4]
- **阅读动作比格式计数更有价值。**Peek 将复制、查找、跳行、滚动恢复列为主要卖点；这些值得纳入原型，但键盘快捷键是否可在扩展中稳定工作要单独验证。[C3]
- **格式覆盖存在实际断点。**FreeLook 的路由记录涉及 `.txt`、`.ts`、无扩展名文件、第三方 UTI 以及系统升级后的 TOML 路由变化。这比再列出几十个扩展名更接近产品可靠性问题。[F2]
- **编码与大文件有明确改进空间。**Glance 当前读取按 UTF-8，普通文件超过 10,000,000 字节即拒绝；这为中文文本、日志与 JSONL 的有限预览留下空间。[C5][C6]

建议产品表述：**“按下空格，让 Markdown、数据、配置与代码都能直接读。”**

避免把“格式最多”作为唯一承诺。应公开可验证的支持矩阵：格式、预览模式、系统版本、实际路由结果、已知限制。

## 3. macOS 平台边界

### 3.1 必须使用现代扩展

Apple 在 macOS 15 发行说明中指出，正在移除已弃用的 Quick Look Generator 插件支持。新项目应使用 `.app` 内的现代 `.appex`，而不是以复制 `.qlgenerator` 到用户目录作为安装方式。[A1]

现代 macOS 可采用视图式 `NSViewController + QLPreviewingController`，或数据式 `QLPreviewProvider + QLPreviewReply`；后者 macOS 12+ 可用。需要交互式源码 / 渲染切换的首版，建议优先评估视图式方案。[A2][A4]

Space、窗口和多文件切换由系统提供。扩展也可能在 Finder 列视图侧栏、Spotlight 等较窄空间出现；布局不能只为大预览浮窗设计。[A3][A5]

### 3.2 文件类型不是扩展名列表

Apple WWDC19 明确要求 `QLSupportedContentTypes` 精确匹配 UTI；声明父类型并不自动匹配全部子类型。因此不能靠 `public.text` 一项覆盖所有文本。[A3]

产品影响：

- 每种格式要同时验证内容识别、UTType 注册与 Finder 实际调用。
- `.ts` 可能与视频传输流类型冲突；不要为了 TypeScript 抢占真实视频类型。[F2]
- `README`、`Dockerfile`、`.env`、`.gitignore`、`.zshrc` 与任意未知扩展名需分别验证。
- `.txt`、`.html` 等有系统 provider 的文件，自定义增强不能先承诺一定接管。
- 不应把注册宽泛的 `public.data` 当作覆盖率捷径；如探索兜底，需要二进制识别、明确范围和对其他文件预览的回归验证。

### 3.3 文件权限与 HTML 的真实含义

预览文件的权限不能直接当作读取相邻任意文件的权限。Glance README 明确说明，本地 Markdown 图片受此限制而不能加载。图片加载应成为早期沙盒 PoC；不能仅靠设置 HTML 的 `baseURL` 就宣称解决。[C1]

QLMarkdown 有成熟的图片嵌入实现，但其扩展 entitlement 配置了针对 `/` 的绝对路径只读 temporary exception。该做法不是无需权限的通用能力，也不等同于用户授予“完全磁盘访问”；是否采用及实际访问边界需独立验证，不能直接复制为默认方案。[S3]

HTML 预览也要定义清楚：本产品建议支持**静态文档的安全渲染**；不执行文件自带脚本、不提交表单、不主动访问网络。依赖 JavaScript 才生成内容的网页，不在首版保真承诺内。Markdown 的内嵌 HTML、SVG 与链接也要遵循同一资源策略。这些是产品设计要求，尚未实现。

应用自己打包的高亮 / Markdown JavaScript 与文档携带的脚本需要区分：前者是可信渲染组件，后者默认不执行。

FreeLook 的开发记录称，其本机 `WKWebView` 需要 `com.apple.security.network.client` 才能正常加载本地 HTML。这是项目作者的环境观察，不是 macOS 通则。PoC 要核实必需的 entitlement，并独立阻断文档的网络资源与导航；“离线”不能只靠移除网络权限保证。[F2]

### 3.4 PDF / Office：系统提供，独立验收

Apple 当前 QuickLookUI 文档列出 Microsoft Office、iWork、文本、PDF 等系统可预览内容。[A2]

本轮还只读检查了当前开发机 **macOS 27.0.1 / Build 26A434** 的系统注册：

| 系统组件 Info.plist | 重点声明 |
|---|---|
| `/System/Library/QuickLook/Office.qlgenerator/Contents/Info.plist` | Word `.doc` / OOXML，Excel `.xls` / OOXML，PowerPoint `.ppt` / OOXML，另有模板、部分宏格式与 CSV 类型 |
| `/System/Library/QuickLook/PDF.qlgenerator/Contents/Info.plist` | `com.adobe.pdf` |
| `/System/Library/QuickLook/Text.qlgenerator/Contents/Info.plist` | plain text、RTF、RTFD、ODT、plist、XML、JSON |
| `/System/Library/QuickLook/Web.qlgenerator/Contents/Info.plist` | HTML、XHTML、SVG、webarchive |

方法：`sw_vers` 获取版本，使用 Python `plistlib` 读取 `CFBundleDocumentTypes → LSItemContentTypes`。这里只证明当前系统声明了相关类型，**没有证明文件视觉效果、分页、全部工作表或兼容性**。系统内部仍存在上述历史目录名，也不代表第三方旧 API 可继续使用。

建议在支持列表里标为“**系统原生预览，本插件保留该行为**”，不要计入本插件实现的渲染格式数。

验收至少包括 `.pdf/.doc/.docx/.xls/.xlsx/.ppt/.pptx` 的中文字体、多页 / 多工作表、合并单元格、图表、密码保护及大文件。使用“通过 / 有限 / 不可预览”记录，不承诺完整 Office 保真或执行宏。

## 4. 竞品与开源候选

### 4.1 最相关的产品

| 项目 | 已核验能力与状态 | 许可证 / 源码 | 对本项目的意义 |
|---|---|---|---|
| **Glance：chamburr 维护分支** | 源码、Markdown、压缩包、Notebook、TSV；现代 Quick Look 扩展；v1.6.0 发布于 2026-09-08，仓库最近推送 2026-10-05 | MIT；Swift + Go | 最接近综合整合定位；适合复用格式分层和 UTI 经验，完整 fork 前需评估渲染层与性能限制。[C1][C2][C5][C6] |
| **FreeLook：neolee/freelook** | Markdown、源码、JSON/XML 格式化、YAML/TOML 等；`WKWebView` + Shiki + markdown-it；工程最低目标 14.6；最近推送 2026-03-25 | MIT | 文本优先路线的重点基座候选；项目较新，需实测成熟度、资源消耗及覆盖。[F1][F2][F3] |
| **QLStephenSwift** | 现代无扩展名文本预览，编码探测、RTF、行号与截断；macOS 15+ | MIT | 编码检测和文本兜底的候选；README 的 NUL 判别与 UTF-16 支持描述需通过样本核验，不能直接采信覆盖承诺。[L2] |
| **QLMarkdown：sbarex** | 专门的 Markdown 渲染，公式 / Mermaid 等能力；现代扩展；v1.5.7 发布于 2026-10-02 | GPL-3.0 | Markdown 能力标杆；接受对应许可路线时可直接研究复用，别与旧同名项目混淆。[S1] |
| **SourceCodeSyntaxHighlight：sbarex** | 多格式语法高亮、主题、配置；现代扩展；v2.1.32 发布于 2026-09-16 | GPL-3.0 | 广覆盖与格式适配的重要参考；注意原有渲染引擎及依赖范围。[S2] |
| **Pique：macadmins/pique** | 面向配置 / 脚本，含 Markdown、TOML、JSONL、结构化 plist；要求 macOS 26+；最近推送 2026-10-16 | Apache-2.0 | 配置与 JSONL 呈现的参考；若首版支持 15，不能直接假设完整移植可用。[P1] |
| **QLJSON：relikd** | 现代 JSON 预览，折叠结构、暗色模式；最近推送 2026-09-18 | MIT | 小而专的 JSON 模块候选，需要结合大文件、数值与顺序保真检查。[J1] |
| **FluxMarkdown** | GFM、KaTeX、Mermaid、目录、图表及 TSV；2026-11-09 仍有推送 | GPL-3.0 / 商业双许可说明 | Markdown 体验参考，功能范围较大；其默认可关闭的使用统计策略不宜直接沿用为本项目默认行为。[C10] |
| **Peek** | 复制、查找、跳行、滚动恢复、Markdown / 源码；官网也列出系统文件类型接管限制 | 本轮未找到可复用公开源码 | 阅读交互标杆；其快捷键方案使用 Accessibility helper，首版不宜直接照搬。[C3] |
| **Unfold** | 官网列出 250+ 类型，覆盖源码、Markdown、JSON、表格、压缩包、电子书等；要求 macOS 15.6+ | 商业产品；本轮未找到可复用公开源码 | 说明“多格式一体化”已有竞争；应比较稳定性和阅读体验。[C4] |

状态来自调研时官方仓库 / release / 工程配置。最近推送可能只是元数据或类型配置变更，不等同于渲染质量、维护承诺或产品活跃用户。

### 4.2 不宜直接作为基座的历史项目

- **samuelmeuli/glance** 是已归档原项目；应研究 `chamburr/glance` 的维护分支，不能把两者状态混写。[C7]
- **旧 QLStephen、QLPrettyPatch** 有历史价值，但旧 `.qlgenerator` 外壳不适合作为新系统基座。可评估其识别规则和解析模块，不能照搬安装方案。[L1][L4]
- 旧文章中的部分 QLColorCode / QuickLookJSON 仓库路径本轮已返回 404，没有将其列作可用代码来源。不要直接根据历史文章选型。
- **PreviewCode / PreviewJson 等 Preview 系列** 可参考 Swift 呈现逻辑；README 明确源码缺少部分资源 / 组件，不能当成可直接完整构建的发行基线。[L5]
- **sindresorhus/quick-look-plugins** 和现代扩展清单适合作为线索，仍需逐项核验维护状态、架构和许可证。[L6][L7]
- `glance.md` 的 Markdown 查看器与开源 Glance 不是同一产品。其发行仓库说明源码不公开，不应作为 MIT 源码来源。[C8]

### 4.3 Glance：接近需求，但不能无成本 fork

源码核验发现：

- `MainVC` 已使用现代 `QLPreviewingController`，但 `WebPreviewVC` 仍构造旧 `WebView` / `mainFrame`，不是 `WKWebView`。[C5][C6]
- `File.read` 使用 UTF-8；普通文件大于 10,000,000 字节直接拒绝预览。[C6][C9]
- 预览读取与生成在主队列调用链里执行，需要评估耗时并迁移重工作。[C6]
- README 说明本地图片不可用、发行包未公证。[C1]

这些事实使其更适合作为**格式分层、适配器、样式和覆盖经验的来源**。它是否比重新搭建统一外壳省力，要靠 PoC 判断，不能仅凭已有功能数决定。

## 5. 建议的文件支持矩阵

“P0”表示首版目标，不代表目前已经实现；“平台验证”表示必须先确认 Finder 路由或权限。先保证常用格式的质量，再扩展长尾。

| 类别 | 建议格式 / 文件名 | 预览方式 | 优先级与边界 |
|---|---|---|---|
| Markdown | `.md .markdown .mdown .mkd .mkdn` | 标题、列表、表格、任务列表、引用、链接、代码块；渲染 / 源码切换 | P0；本地图片为平台验证门槛；公式、Mermaid P1 |
| JSON | `.json` | 原文 / 格式化、高亮、明确错误位置；折叠树可后续增加 | P0；路由验证；不能在格式化中损坏大整数或悄悄覆盖重复键 |
| JSON Lines | `.jsonl .ndjson` | 逐行识别、行号、记录数 / 错误行提示、有限读取 | P0；坏行不使整份文件不可读；不当成单个 JSON 解析 |
| 配置文本 | `.yaml .yml .toml .properties .ini .conf .cfg` | 高亮，保留原文、注释、顺序 | P0；`.conf/.cfg` 不假定只有一种语法；结构树 P1 |
| 普通文本 / 日志 | `.txt .text .log .out .err` | 等宽文本、换行、行号、大文件截取 | P0 阅读目标；TXT 默认沿用系统，增强接管需平台验证 |
| HTML | `.html .htm .xhtml` | 系统静态渲染；自定义模式探索渲染 / 源码切换 | 原生能力首版保留；自定义接管与本地资源需平台验证 |
| XML / plist | `.xml .plist .mobileconfig .entitlements` | 高亮；二进制 plist 转可读表示 | P1；部分有系统 provider，需逐项验证 |
| 表格文本 | `.csv .tsv .tab` | 有行列边界的表格 / 原文 | P1；CSV 系统路由需验证，不能简单按逗号切割 |
| 源码 / 查询 | Swift、JS/TS、Python、Go、Rust、C/C++、Java、Shell、SQL、CSS 等 | 复用统一高亮器，行号 / 换行 | 首版选择常用集；扩展名冲突要单独记录 |
| 无扩展名 / dotfile | `README LICENSE CHANGELOG Dockerfile Makefile .env .gitignore .zshrc` | 文件名规则 + 文本探测，保守兜底 | 内容识别 P0；系统调用覆盖需平台验证 |
| patch / diff | `.patch .diff` | 高亮与行边界 | P1；可用统一高亮器，无需独立旧插件 |
| PDF / Office | `.pdf .doc .docx .xls .xlsx .ppt .pptx` | 系统原生预览 | 首版保留并验收，不自带办公渲染引擎 |
| 扩展文档 | `.jsonc .json5 .ipynb .rst .adoc .tex .epub` | 按真实需求追加 | P2；Notebook 不执行代码，JSONC/JSON5 不冒充标准 JSON |
| 可执行文档 | `.mdx .Rmd .qmd` 等 | 可先作为文本；静态子集另定义 | 不因识别扩展名就承诺执行 JSX、R、Python 或构建整个项目 |

TXT、HTML 已有系统预览并不妨碍产品满足“按 Space 能看”的需求；但若要求这类文件也拥有统一主题、查找和切换，则要先验证第三方接管的可行性。

### 5.1 几项容易被“支持”二字掩盖的要求

- **中文编码**：先正确处理 UTF-8、UTF-8 BOM、UTF-16 LE/BE；再评估 GB18030 / GBK、Big5、Shift-JIS。不要依靠一次猜测默默产出乱码；低置信度时提示编码并提供有限切换。
- **properties**：保留原始转义与注释；是否解释 `\uXXXX` 另设可读视图，不改写原文件。
- **JSON 格式化**：保留原文作为权威视图。避免用 JavaScript 数字再序列化导致大整数改变；保留键顺序和重复键的处理规则需要明确。
- **大文件**：显示前若干字节 / 行 / 记录与“已截断”说明。不要将整份 GB 日志或 JSONL 读入内存、构造成一个巨大 DOM。
- **二进制判别**：不能在识别 BOM 前仅凭 NUL 字节认定二进制，UTF-16 本身常包含 NUL。
- **失败可读**：格式错误先退回受限的原文预览；系统未调用插件、文件无法解码、资源被阻止是不同原因，要分别说明。

## 6. 开源复用方案

### 6.1 三条可选路线

| 路线 | 优点 | 代价 | 建议 |
|---|---|---|---|
| 完整 fork Glance | 现成综合功能、格式分层、现代扩展入口 | 旧 Web 渲染层、Go 构建链、编码 / 大文件 / 图片 / 分发问题 | 作为对照原型；不直接认定总成本最低 |
| 以 FreeLook / 小型现代外壳为基础，选取其他项目模块 | 更贴近 Markdown + 数据 + 配置，容易统一资源策略 | 需要逐项补齐 JSONL、文本兜底与产品细节；新项目成熟度待验证 | **首选评估路线** |
| 采用 sbarex 系列能力并制定 GPL 发行方案 | Markdown 与源码能力成熟，符合开源方向 | 需要梳理多个引擎、设置及依赖；按实际许可证安排发行 | 若复用成熟功能比简化引擎更重要，可优先考虑 |

最终选择应依据同一批样本的渲染效果、路由成功率、冷启动、内存、体积与维护成本，而不是语言偏好或 star 数。

### 6.2 推荐的最小模块组合

| 模块 | 候选与已核验许可证 | 使用建议 |
|---|---|---|
| 扩展 / 宿主 | FreeLook（MIT）、Glance（MIT） | 复用启动、共享设置、适配器等必要部分；保持一个清晰的格式入口 |
| 文本读取 / 编码 | FreeLook FileLoader、QLStephenSwift FileAnalyzer / TextFormatter（均 MIT） | 优先抽取有界读取与编码识别逻辑；针对 UTF-16、中文旧编码和二进制误判建立样本。[F4][L2] |
| Markdown | markdown-it（MIT） | 本地打包；不需要分发 Node runtime；与统一高亮器配合。[R1] |
| 代码高亮 | highlight.js（BSD-3-Clause），或 FreeLook 现有 Shiki | 原型先保留既有方案作基线；再比较按需语言包，避免同时分发多个完整高亮器。[R2][F3] |
| 原生 Markdown 备选 | Swift Markdown（Apache-2.0 + Runtime Library Exception；底层另有 notices） | 若原生渲染收益得到证实再采用；它是 parser / AST，不是完整查看器。[R3] |
| JSON | QLJSON（MIT）或自有有界格式化层 | 先审查数值、重复键、深度及大小限制，避免把 DOM 树做成重型编辑器。[J1] |
| YAML | 高亮优先；结构化需求再评估 Yams（MIT，含 LibYAML） | 首版无需为了“支持 YAML”增加解析 / 重序列化链路。[R4] |
| TOML / INI / properties | 统一高亮器；需要语义视图再评估 TOMLDecoder（MIT） | 高亮能满足多数快速阅读需求，保留注释。[R5] |
| CSV / TSV | SwiftCSV（MIT） | 处理引号、多行字段、分隔符与有界读取；避免手写简单 split。[R6] |

统一使用系统 `WKWebView` 不等于资源成本为零。WebContent 进程、Shiki 资源、语法包、字体与图表库都要计入测量；不能因没有 Electron 就宣称性能更好。

### 6.3 复用与许可证记录

建议为每个采用的模块记录：上游仓库、固定 tag / commit、复制文件、修改说明、许可证、依赖、主题 / 字体 / 图片来源及更新方式。保留必要的 copyright、LICENSE、NOTICE 与第三方声明。

项目根许可证不能代表每个依赖。MIT / Apache 路线与直接采用 GPL 源码的路线应在选型时分别明确，不能把复制来的 GPL 模块统一标成自有 MIT。具体分发按选定版本的实际许可文件核验；本轮未完成整包许可证审计。

模块复用的重点入口：FreeLook 的 `FileLoader.swift`、`UTIMapper.swift`、`renderer.js`；QLStephenSwift 的 `FileAnalyzer.swift` / `TextFormatter.swift`；Glance 的 Preview 协议和 factory；QLMarkdown 的 `PreviewProvider.swift` 及 Markdown 扩展。QLMarkdown 当前使用数据式 `QLPreviewProvider + QLPreviewReply`，不应将其误写成 `WKWebView` 自绘方案。[F4][L2][S4]

## 7. “轻量”应如何定义

建议将轻量定义为可以验收的行为：

- 一个小型设置 / 诊断宿主；普通预览无需宿主常驻、无需后台服务器。
- 首版无需全局快捷键监听或 Accessibility 权限；查找 / 复制先验证扩展内部交互，快捷键增强另作可选评估。
- 渲染资源随应用分发，不从 CDN 下载；默认不联网、不上传文档。
- 不捆绑 Node、Electron、浏览器内核或完整 Office 套件；系统 WebKit 可用但要测进程成本。
- 文件读取、解析、高亮有大小 / 时间 / 深度边界；切换文件后可以取消旧任务。
- 同一高亮模块服务源码和 Markdown 代码块，避免多个插件重复携带引擎。

以下仅是 **PoC 验收目标草案**，不是已测成绩，也不是平台保证：

| 指标 | 初始目标 / 测量方式 |
|---|---|
| 常用小文件 | 100 KB 以内样本，暖启动首屏 p95 争取小于 300 ms；冷启动单独记录 |
| 大文本 | 100 MB 与 1 GB 日志 / JSONL：有界读取、可取消，首屏争取 1 秒内出现；允许截断 |
| 内存 | 记录扩展与 WebContent 的合计峰值，确认不会随完整文件大小线性膨胀 |
| 包体 | 同时记录下载、安装及各引擎资源体积，先建立原型基线再设硬预算 |
| 空闲行为 | 没有预览时不靠宿主常驻工作；系统托管的扩展进程行为单独观察 |
| 原生能力 | 安装前后 PDF / Office 预览回归结果一致；卸载后无额外关联修复步骤 |

LibreOffice 具备 headless / 转换命令，但完整办公引擎与本项目首版的轻量目标不匹配。其官方 macOS 系统要求提到最多 800 MB 可用磁盘空间；这不能当作嵌入包的精确大小。[O1][O2]

## 8. 建议的首版范围与推进顺序

### 阶段 A：用最小原型消除平台不确定性

先比较 FreeLook 路线与 Glance 精简路线，不先开发完整设置界面。

1. 在 macOS 15、26、当前 27 的可用测试环境验证核心文件 UTType 与实际 provider；区分干净环境与已装同类插件环境。
2. 验证 Markdown 同目录 / 子目录图片、越界路径、软链接与远程 URL 的行为，确定默认可用范围与授权方式。
3. 用 UTF-8 / UTF-16 / GB18030、长行、坏 JSONL、深层 JSON、100 MB / 1 GB 文件测降级与取消。
4. 验证 Space、Esc、多文件切换、窄侧栏、选中文本、复制、搜索按钮与键盘焦点。
5. 确定“系统处理 / 插件增强 / 暂不支持”矩阵，再选择完整 fork 或模块复用。

本阶段产物应是实测矩阵与选型记录。未通过的 TXT / HTML 接管、本地图片等项目不进入无条件支持承诺。

### 阶段 B：文本优先的可发布 MVP

- Markdown 基础渲染 / 源码切换，按阶段 A 结果提供图片策略。
- JSON 格式化与原文；JSONL 逐行有限预览。
- YAML、TOML、properties、INI、常用代码、日志高亮。
- UTF-8 / UTF-16，依据实测增加中文编码处理。
- 暗色 / 浅色、字体大小、换行、行号、复制；搜索交互依原型结论确定。
- 明确的截断、错误、资源受限提示；PDF / Office 原生预览回归。
- 简单的启用说明和路由诊断；签名 / 公证的可安装包、源码构建说明与第三方声明。

### 阶段 C：由实际使用推动扩展

优先比较 CSV/TSV 表格、Mermaid / 公式、JSON 折叠树、Notebook 静态预览；再考虑 EPUB、压缩包等。它们都不应拖慢基本文本预览。

首版不做文档编辑、云同步、AI 摘要、代码执行、Office 替代引擎或需要系统快捷键拦截的独立预览窗口。

## 9. 开源产品与用户验证

建议分发顺序为 GitHub Releases 的签名 / 公证应用，再补 Homebrew cask；Mac App Store 的沙盒、发布与许可适配另评估。旧插件清单里常见的移除 quarantine 命令，不应成为正式产品默认安装流程。

仓库应提供：可复现构建步骤、格式支持与已知限制、样例文件、截图、第三方声明，以及不上传原文的故障反馈方式。诊断应围绕 OS 版本、启用状态、UTType 和实际 provider；不必自动扫描用户文档。

建议找 6–10 位目标用户试用统一样本与各自日常文件，重点验证：

| 问题 | 观察信号 |
|---|---|
| 预览是否替代了打开编辑器的动作？ | 任务能否在预览中完成；仍打开编辑器的原因 |
| 哪些格式值得首版投入？ | 用户实际遇到的文件，而非想象中的格式清单 |
| 统一体验比多个插件更有价值吗？ | 安装、切换主题、冲突排查是否明显简化 |
| 大文件与本地图片是否关键？ | 真实出现频率、失败后的工作流影响 |
| 怎样算轻量？ | 对启动延迟、内存、包体、权限与后台进程的实际反馈 |

这些验证完成前，不建议估算精确市场规模或宣称产品优于现有方案。

## 10. 来源与核验入口

所有在线来源访问于 2026-11-10；分支内容会变化，实际采用源码时应固定 commit / tag。

### Apple 官方

- [A1 — macOS 15 Release Notes](https://developer.apple.com/documentation/macos-release-notes/macos-15-release-notes)
- [A2 — QuickLookUI](https://developer.apple.com/documentation/quicklookui/)
- [A3 — WWDC19：What's New in File Management and Quick Look](https://developer.apple.com/videos/play/wwdc2019/719/)
- [A4 — QLPreviewProvider](https://developer.apple.com/documentation/quicklookui/qlpreviewprovider)
- [A5 — Apple Support：Preview files on your Mac](https://support.apple.com/guide/mac-help/preview-a-file-mchlgtd_prev01/mac)
- [A6 — preparePreviewOfFile](https://developer.apple.com/documentation/quicklookui/qlpreviewingcontroller/preparepreviewoffile(at:completionhandler:))：后台工作与完成回调约束。

### 综合项目与竞品

- [C1 — chamburr/glance README](https://github.com/chamburr/glance#readme)
- [C2 — Glance v1.6.0](https://github.com/chamburr/glance/releases/tag/v1.6.0)、[MIT 许可](https://github.com/chamburr/glance/blob/main/LICENSE.md)
- [C3 — Peek 官方网站](https://www.bigzlabs.com/peek)
- [C4 — Unfold 官方网站](https://flew.gg/unfold)
- [C5 — Glance WebPreviewVC.swift](https://github.com/chamburr/glance/blob/main/QLPlugin/Views/PreviewVCs/WebPreviewVC.swift)
- [C6 — Glance MainVC.swift](https://github.com/chamburr/glance/blob/main/QLPlugin/MainVC.swift)
- [C7 — samuelmeuli/glance 仓库元数据](https://api.github.com/repos/samuelmeuli/glance)
- [C8 — maging-studio/glance 发行仓库](https://github.com/maging-studio/glance)
- [C9 — Glance File.swift](https://github.com/chamburr/glance/blob/main/QLPlugin/Utils/File.swift)
- [F1 — FreeLook](https://github.com/neolee/freelook)、[MIT 许可](https://github.com/neolee/freelook/blob/main/LICENSE.md)
- [F2 — FreeLook UTType 调研](https://github.com/neolee/freelook/blob/main/docs/uti.md)、[格式矩阵](https://github.com/neolee/freelook/blob/main/docs/file-types.md)
- [F3 — FreeLook WKWebView 实现](https://github.com/neolee/freelook/blob/main/FreeLook/QuickLookExtension/PreviewViewController.swift)、[依赖](https://github.com/neolee/freelook/blob/main/WebRenderer/package.json)、[系统最低目标](https://github.com/neolee/freelook/blob/main/FreeLook/FreeLook.xcodeproj/project.pbxproj)
- [C10 — FluxMarkdown](https://github.com/xykong/flux-markdown)、[双许可说明](https://github.com/xykong/flux-markdown#-license)、[GPL 文件](https://github.com/xykong/flux-markdown/blob/master/LICENSE)
- [F4 — FreeLook FileLoader](https://github.com/neolee/freelook/blob/main/FreeLook/QuickLookExtension/FileLoader.swift)、[UTIMapper](https://github.com/neolee/freelook/blob/main/FreeLook/QuickLookExtension/UTIMapper.swift)、[renderer.js](https://github.com/neolee/freelook/blob/main/WebRenderer/src/renderer.js)
- [S1 — sbarex/QLMarkdown](https://github.com/sbarex/QLMarkdown)、[v1.5.7](https://github.com/sbarex/QLMarkdown/releases/tag/1.5.7)、[GPL-3.0 许可](https://github.com/sbarex/QLMarkdown/blob/main/LICENSE.txt)
- [S2 — SourceCodeSyntaxHighlight](https://github.com/sbarex/SourceCodeSyntaxHighlight)、[v2.1.32](https://github.com/sbarex/SourceCodeSyntaxHighlight/releases/tag/2.1.32)、[GPL-3.0 许可](https://github.com/sbarex/SourceCodeSyntaxHighlight/blob/master/LICENSE.txt)
- [S3 — QLMarkdown 图片权限配置](https://github.com/sbarex/QLMarkdown/blob/main/QLExtension/QLExtension.entitlements)
- [S4 — QLMarkdown PreviewProvider](https://github.com/sbarex/QLMarkdown/blob/main/QLExtension/PreviewProvider.swift)
- [P1 — macadmins/pique](https://github.com/macadmins/pique)、[Apache-2.0 许可](https://github.com/macadmins/pique/blob/main/LICENSE)
- [J1 — relikd/QLJSON](https://github.com/relikd/QLJSON)、[MIT 许可](https://github.com/relikd/QLJSON/blob/main/LICENSE)

### 历史项目与发现入口

- [L1 — QLStephen](https://github.com/whomwah/qlstephen)
- [L2 — QLStephenSwift](https://github.com/MyCometG3/QLStephenSwift)、[MIT 许可](https://github.com/MyCometG3/QLStephenSwift/blob/main/LICENSE)、[FileAnalyzer](https://github.com/MyCometG3/QLStephenSwift/blob/main/QLStephenSwift/QLStephenSwiftPreview/FileAnalyzer.swift)、[TextFormatter](https://github.com/MyCometG3/QLStephenSwift/blob/main/QLStephenSwift/QLStephenSwiftPreview/TextFormatter.swift)
- [L4 — QLPrettyPatch](https://github.com/atnan/QLPrettyPatch)
- [L5 — PreviewJson](https://github.com/smittytone/PreviewJson)、[PreviewCode](https://github.com/smittytone/PreviewCode)
- [L6 — Quick Look plugins 清单](https://github.com/sindresorhus/quick-look-plugins)
- [L7 — 现代 .appex 扩展清单](https://github.com/Oil3/List-of-modern-Quick-Look-extensions)

### 渲染模块与 Office 参考

- [R1 — markdown-it](https://github.com/markdown-it/markdown-it)、[MIT 许可](https://github.com/markdown-it/markdown-it/blob/master/LICENSE)
- [R2 — highlight.js](https://github.com/highlightjs/highlight.js)、[BSD-3-Clause 许可](https://github.com/highlightjs/highlight.js/blob/main/LICENSE)
- [R3 — Swift Markdown](https://github.com/swiftlang/swift-markdown)、[许可](https://github.com/swiftlang/swift-markdown/blob/main/LICENSE.txt)、[底层 notices](https://github.com/swiftlang/swift-cmark/blob/gfm/COPYING)
- [R4 — Yams](https://github.com/jpsim/Yams)、[许可](https://github.com/jpsim/Yams/blob/main/LICENSE)
- [R5 — TOMLDecoder](https://github.com/dduan/TOMLDecoder)、[许可](https://github.com/dduan/TOMLDecoder/blob/main/LICENSE.md)
- [R6 — SwiftCSV](https://github.com/swiftcsv/SwiftCSV)、[许可](https://github.com/swiftcsv/SwiftCSV/blob/master/LICENSE)
- [O1 — LibreOffice CLI](https://help.libreoffice.org/latest/en-US/text/shared/guide/start_parameters.html)
- [O2 — LibreOffice 系统要求](https://www.libreoffice.org/system-requirements/)

仓库状态日期另核验了 GitHub 官方元数据：[FreeLook](https://api.github.com/repos/neolee/freelook)、[Glance fork](https://api.github.com/repos/chamburr/glance)、[Pique](https://api.github.com/repos/macadmins/pique)、[QLJSON](https://api.github.com/repos/relikd/QLJSON)。

[A1]: https://developer.apple.com/documentation/macos-release-notes/macos-15-release-notes
[A2]: https://developer.apple.com/documentation/quicklookui/
[A3]: https://developer.apple.com/videos/play/wwdc2019/719/
[A4]: https://developer.apple.com/documentation/quicklookui/qlpreviewprovider
[A5]: https://support.apple.com/guide/mac-help/preview-a-file-mchlgtd_prev01/mac
[A6]: https://developer.apple.com/documentation/quicklookui/qlpreviewingcontroller/preparepreviewoffile(at:completionhandler:)
[C1]: https://github.com/chamburr/glance#readme
[C2]: https://github.com/chamburr/glance/releases/tag/v1.6.0
[C3]: https://www.bigzlabs.com/peek
[C4]: https://flew.gg/unfold
[C5]: https://github.com/chamburr/glance/blob/main/QLPlugin/Views/PreviewVCs/WebPreviewVC.swift
[C6]: https://github.com/chamburr/glance/blob/main/QLPlugin/MainVC.swift
[C7]: https://api.github.com/repos/samuelmeuli/glance
[C8]: https://github.com/maging-studio/glance
[C9]: https://github.com/chamburr/glance/blob/main/QLPlugin/Utils/File.swift
[C10]: https://github.com/xykong/flux-markdown
[F1]: https://github.com/neolee/freelook
[F2]: https://github.com/neolee/freelook/blob/main/docs/uti.md
[F3]: https://github.com/neolee/freelook/blob/main/FreeLook/QuickLookExtension/PreviewViewController.swift
[F4]: https://github.com/neolee/freelook/blob/main/FreeLook/QuickLookExtension/FileLoader.swift
[S1]: https://github.com/sbarex/QLMarkdown
[S2]: https://github.com/sbarex/SourceCodeSyntaxHighlight
[S3]: https://github.com/sbarex/QLMarkdown/blob/main/QLExtension/QLExtension.entitlements
[S4]: https://github.com/sbarex/QLMarkdown/blob/main/QLExtension/PreviewProvider.swift
[P1]: https://github.com/macadmins/pique
[J1]: https://github.com/relikd/QLJSON
[L1]: https://github.com/whomwah/qlstephen
[L2]: https://github.com/MyCometG3/QLStephenSwift
[L4]: https://github.com/atnan/QLPrettyPatch
[L5]: https://github.com/smittytone/PreviewJson
[L6]: https://github.com/sindresorhus/quick-look-plugins
[L7]: https://github.com/Oil3/List-of-modern-Quick-Look-extensions
[R1]: https://github.com/markdown-it/markdown-it
[R2]: https://github.com/highlightjs/highlight.js
[R3]: https://github.com/swiftlang/swift-markdown
[R4]: https://github.com/jpsim/Yams
[R5]: https://github.com/dduan/TOMLDecoder
[R6]: https://github.com/swiftcsv/SwiftCSV
[O1]: https://help.libreoffice.org/latest/en-US/text/shared/guide/start_parameters.html
[O2]: https://www.libreoffice.org/system-requirements/
