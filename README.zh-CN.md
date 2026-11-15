<img src="docs/brand/orbispeek-icon.png" width="96" alt="OrbisPeek 应用图标">

# OrbisPeek

**按下空格，看见更多。**

**[下载 v0.1.1 预览版](https://github.com/Kairan-Peng/OrbisPeek/releases/tag/v0.1.1)** — macOS 15+，Universal，build 1227。DMG / ZIP 已使用 Developer ID 签名，**尚未公证**，首次打开可能被系统拦截。安装前请阅读[安装、目录授权与限制说明](docs/installing.md)。

一个开源、轻量的 macOS Quick Look 扩展。在 Finder 中选中文件，按空格阅读 Markdown、JSON/JSONL、配置、日志和源码。宿主提供应用介绍、目录授权管理和可选的无后缀文本预览开关。

项目原名为 Quicklook。内部模块名、bundle identifier 和资源协议继续保留原名，以兼容已有配置。

目前是可构建、可运行的首版开发原型。基于 FreeLook 和 QLStephenSwift 的 MIT 代码与适配经验，复用 markdown-it、highlight.js 和 jsonc-parser；宿主和扩展共享同一个渲染组件。运行时不携带 Node 或 Electron。

## 已实现

- Markdown 表格、任务列表、代码高亮、渲染 / 原文切换，以及支持有界整数宽高的受控 `<img>` 本地图片。
- HTML / HTM / XHTML 保留系统预览；1225 已移除本扩展的 HTML 类型声明，共享 HTML 渲染实现保留但不作为当前产品入口。
- JSON 保留大整数、重复键、键顺序和原始转义的格式化；无效内容退回原文。
- JSONL / NDJSON 逐行查看，坏行不影响其他记录。
- YAML、TOML、properties、INI、日志与常用源码高亮。
- 常规已支持格式使用 UTF-8 / UTF-16 / UTF-32 BOM 识别；无 BOM UTF-16 与中文旧编码使用有提示的推测。
- **无后缀文本预览默认关闭**：可在 App 页面开启，对实际类型为 `public.data`、主要无后缀的文件尝试只读文本；更改后请关闭并重新打开预览。仅接受严格 UTF-8 或带明确 BOM 的 UTF-16/32，不进行旧编码推测。读取阶段拒绝恢复系统原图标 / 文件信息，不保证调用下一提供器渲染正文。
- 每次最多读取 512 KiB + 4 字节，限制显示行数、长行高亮和图片资源；大文件仍可查看前缀。
- 暗色 / 浅色、换行、行号和选区纯文本复制。单行工具栏提供模式与换行图标。
- 默认不请求文档中的网络资源，不执行文档自带脚本。
- 单页应用介绍与目录管理：首次使用可选择常用项目或笔记目录，支持添加及逐项移除只读授权；扩展接收后宿主不必常驻。
- 本地图片不可读时显示简短授权提示和入口，正常预览不增加控件；本机 Finder 无法直接唤起管理页时提供手动步骤。

[类型清单](docs/file-types.md)目前包含 **230 种后缀、87 个格式组、56 个文件名规则**。这些是可识别范围；Finder 是否调用扩展还取决于实际 UTType 和其他已安装的插件。TXT / PDF / Office 等继续由系统预览，不改变默认打开应用。

当前已签名重装 **0.1.1（1226）**。App 单页保留 logo、名称、slogan、目录管理，并加入一个紧凑的“无后缀文本预览”开关；缺失或损坏的设置默认关闭，不从 1225 自动迁移为开启。真实 Finder 同一路径的关闭 → 开启 → 关闭通过，退出宿主后设置仍生效，重开 App 保留相应状态；开启后二进制回退、关闭时 Markdown 渲染 / 原文及 HTML 系统预览通过。96 项 Swift 检查（含 6 项新增设置测试）及 8 项离屏布局检查通过，最终维持关闭。见[默认关闭开关验收](docs/extensionless-opt-in-validation-2026-11-15.md)。查找、打开方式及“打开文件… / ⌘O”继续移除，没有新增后台组件或权限；本轮未重验 Finder 剪贴板复制。

以下版本段落保留历史验收，旧独立阅读器入口已由本轮预览插件定位取代；[历史输入与路由结果](docs/preview-interface-validation-2026-11-12.md)不改写为成功。

1225 曾在没有开关时加入未分类文本尝试，对 19 份文件完成 20 次 Finder 内容状态观察，覆盖 Unicode、空文件、大文件前缀、读取拒绝、同路径文本变二进制及原生格式控制。1226 将其改为用户明确开启；**194 项静态声明保持：193 个语义类型 + 直接 `public.data`**，关闭时在运行时交回系统，不读取文档正文。旧结果见[未分类文本验证与边界](docs/unclassified-text-validation-2026-11-15.md)。

1220 已构建并重新安装，移除“打开方式 → OrbisPeek”以及“文件 → 打开文件… / ⌘O”的阅读器入口；真实菜单、Finder 打开方式列表及 Markdown 渲染 / 原文 / 换行检查通过。查找继续移除，不增加后台组件，七份样例的默认打开应用保持。该版本的 HTML 两个精确声明仍在 195 项扩展清单中，但新建 HTML/HTM/有效 XHTML 的 Finder 复验仍由系统预览，未实现本扩展工具栏接管。见[1220 验收与未完成项](docs/preview-plugin-only-validation-2026-11-15.md)、[当前功能清单](docs/app-features-2026-11-14.md)。

2026-11-14 已在 1208 修复 Finder 复制命令递归崩溃，渲染与原文选区 ⌘C、纯文本及实际粘贴均通过。内部工具栏不再重复显示文件名，保留元数据与模式 / 换行图标。见[修复验收](docs/finder-copy-repair-2026-11-14.md)、[1207 原失败记录](docs/finder-copy-validation-2026-11-14.md)与[当前完整功能清单](docs/app-features-2026-11-14.md)。

1209 已补受控 Markdown `<img>`：在合成目录授权下，Finder 图片、README 的 96px 尺寸、原文往返及两种模式的纯文本复制 / 实际粘贴通过；临时授权已撤销，见[图片验收与范围](docs/markdown-img-validation-2026-11-14.md)。

1214 已将宿主简化为介绍与目录管理单页，加入首次空态引导及图片受限入口。真实目录添加、逐项移除、图片恢复与原有授权保留通过。本机 Finder 的公开唤起接口返回失败，预览会显示明确的手动设置步骤；独立阅读器可直接进入管理页。见[引导验收与限制](docs/permission-onboarding-validation-2026-11-14.md)。

1218 首次引导默认定位真实用户主目录，并保留其他目录入口。原生面板的默认位置、取消、确认保存、重开保留及 Finder 图片 / 原文往返已实测通过，未增加后台组件。见[个人目录引导验收](docs/home-directory-onboarding-validation-2026-11-14.md)。

1219 修复原文等编号视图的行号被选中问题：实际 WebKit 回归与 Finder 跨行拖选、全选验收通过，纯文本复制投影保持。见[行号选区修复](docs/line-number-selection-validation-2026-11-14.md)。

2026-11-11 在更名前已对全部 **227 种后缀逐一执行 Finder 预览验收**：macOS 27.0.1 / Apple Silicon、0.1.1（12）上，**223 项显示实际内容**（220 项本扩展、3 项系统文本预览），没有未检查项或其他失败。`.ts`、`.mts`、`.edn`、`.exs` 四份文本样本只显示文件信息；按维护者选择保留视频、Adobe 数据和 Logic 音色格式兼容，明确列为限制，不计入内容通过。

详见 [227 项逐行报告](docs/finder-coverage.md)、[机器可读结果](docs/finder-coverage.json)、[明确的兼容边界政策](samples/coverage/accepted-limitations.json) 和 [验收证据规则](docs/finder-coverage-reporting.md)。样本是实际磁盘文件中的代表性语法，不能代替所有文档内容、无后缀文件、dotfile 和其他系统版本的验证。

## 构建

需要 macOS 15+、Xcode 16+、XcodeGen、Python 3，以及 Node 22.13+ 或 24+。当前开发机实际验证为 macOS 27.0.1 / Xcode 27.2 / Apple Silicon；尚未验证其他系统与 Intel。

```sh
./scripts/build
```

开发应用位于 `.build/xcode/Build/Products/Debug/OrbisPeek.app`。脚本根据单一类型清单生成注册声明，安装锁定的本地 npm 依赖、构建网页资源并生成 Xcode 工程。默认使用仅供本机运行的 ad-hoc 签名，尚未公证或发布。

打开应用，前往“系统设置 → 通用 → 登录项与扩展 → 快速查看”，启用 OrbisPeek Preview。若安装过同类插件，需要选择实际使用的预览扩展；不应把所有插件同时开启后仍由其他 provider 渲染的结果当作本项目成功。

主页面保留介绍、目录管理和“无后缀文本预览”开关，原安装自检、示例和诊断界面已移除；开发验证工具继续保留。

### Release 测试包

```sh
QUICKLOOK_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
QUICKLOOK_TEAM_ID='TEAMID' \
./scripts/package-release
```

默认构建签名的 arm64 / x86_64 Universal Release，生成 ZIP、DMG、校验和与 manifest，并重新解包、挂载验证。默认不上传 Apple 公证服务。安装包应放入应用程序目录后运行；详细的发布、回退与可选公证流程见 [发布说明](docs/releasing.md)，无需重启的安装验收见 [验收方案](docs/beta-acceptance.md)。

### 可选：启用本地图片目录授权

App Group 能力需要正确的开发者签名。使用你自己的现有 Developer ID 与 Team ID：

```sh
QUICKLOOK_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
QUICKLOOK_TEAM_ID='TEAMID' \
./scripts/build --directory-access
```

首次引导提供“允许读取个人目录…”，系统选择器默认定位账号主目录，由用户确认一次只读授权；也可点击“选择其他目录…”选择项目或笔记库。已有授权时通过 ＋ 选择这两个入口，对应的 − 只移除该项。关闭已有预览，再使用 Space 预览其中的 Markdown；扩展会把移交权限转存为自己的持久书签，以后不需要宿主常驻。移除授权后关闭并重新打开预览即可生效。主目录授权不绕过系统对私有应用数据的保护；不增加后台组件。[个人目录引导验收记录](docs/home-directory-onboarding-validation-2026-11-14.md)

普通 ad-hoc 构建保留文本预览，但不启用共享目录授权。签名脚本不创建证书、不上传或公证应用；本机已验证真实扩展的授权、退出宿主后的新进程恢复与撤销，尚未验证整机重启。[机制与证据](docs/local-image-access.md)

## 验证

```sh
./scripts/test
python3 scripts/make-fixtures.py --large --inspect
python3 scripts/validate-core.py
swift scripts/probe-routing.swift --output .build/routing/current.json samples/fixtures
```

- `scripts/test` 检查生成文件、Swift 核心和 JavaScript 渲染逻辑。
- `validate-core.py` 使用真实 WKWebView 检查核心格式、中文编码、JSON 精度、坏行、资源边界和大文件前缀，报告写入 `.build/validation/core-results.json`。
- `probe-routing.swift` 检查文件的真实 UTType 与声明是否精确匹配；它不证明系统选择了哪个 provider。
- `--large` 在忽略目录中创建 100 MiB 重复日志及 1 GiB 稀疏 JSONL。后者只有前缀是有效 JSONL，用于有界读取验证，不代表解析了整份 1 GiB 文档。

实测记录与限制见 [首轮验证结果](docs/validation-results.md)，样本设计见 [验证方案](docs/validation-plan.md)。

安装自检、插件清理、宿主退出 / 权限撤销、卸载与最终 ZIP 重装的结果见 [0.1.1 本地验收记录](docs/beta-validation-2026-11-11.md)。当前最终包未提交公证。

## 已知边界

- Quick Look 沙盒默认只有被预览文件的权限。未配置可选签名构建或未授权目录时，本地图片会显示资源受限提示。当前不使用全盘只读 temporary exception。
- 图片只允许文档目录内的光栅文件；拒绝远程、绝对路径、父目录和符号链接越界。使用受限尺寸的首帧图像，不播放动画，不加载 SVG。
- `.ts/.mts` 可能被系统识别为视频，`.r/.edn/.exs/.d` 等也可能与其他格式冲突；本项目保留这些系统类型，不以抢占它们换取表面覆盖率。
- 无后缀文本预览须用户开启，且只对实际类型直接为 `public.data` 的文件做保守文本尝试。无后缀和 dotfile 也可能有其他类型，因此不能保证全部接管。每个新请求读取有 4 KiB 上限、原子写入的共享设置；缺失或无效则关闭。普通未配置 App Group 的构建无法使用此开关。
- 任意陌生后缀通常产生 `dyn.*`，隔离实测中 `public.data`、`public.item`、`public.content` 祖先声明均未匹配。生产不枚举实验动态类型，也不承诺所有未知后缀或所有系统版本的回退。
- 系统图标 / 元数据回退限于首次或关闭后重开预览的读取阶段拒绝，不代表自动调用下一提供器。异步 WebKit 失败仍显示本应用错误界面；隐藏 / 恢复期间文件变坏时显示“无法恢复预览。请关闭后重新按空格预览。”，关闭重开后重新执行严格文本策略。
- 旧编码的极短样本有歧义；推测结果有提示，不承诺自动识别所有编码。
- PDF / Office 使用系统能力，没有实现办公引擎，也没有承诺完整 Office 版式保真。

## 开源复用

项目仓库：[Kairan-Peng/OrbisPeek](https://github.com/Kairan-Peng/OrbisPeek)。参与方式见 [CONTRIBUTING.md](CONTRIBUTING.md)。

本项目使用 MIT 许可。改编文件保留上游版权，固定来源、修改范围及各依赖许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 和 [渲染器依赖声明](WebRenderer/THIRD_PARTY.md)。运行时许可证随应用资源分发。

产品背景见 [产品调研](docs/product-research-2026-11-10.md)。
