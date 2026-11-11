# Quicklook

一个开源、轻量的 macOS Quick Look 扩展。在 Finder 中选中文件，按空格阅读 Markdown、JSON/JSONL、配置、日志和源码。

目前是可构建、可运行的首版开发原型。基于 FreeLook 和 QLStephenSwift 的 MIT 代码与适配经验，复用 markdown-it、highlight.js 和 jsonc-parser；宿主和扩展共享同一个渲染组件。运行时不携带 Node 或 Electron。

## 已实现

- Markdown 表格、任务列表、代码高亮，以及渲染 / 原文切换。
- JSON 保留大整数、重复键、键顺序和原始转义的格式化；无效内容退回原文。
- JSONL / NDJSON 逐行查看，坏行不影响其他记录。
- YAML、TOML、properties、INI、日志与常用源码高亮。
- UTF-8 / UTF-16 / UTF-32 BOM 识别；无 BOM UTF-16 与中文旧编码使用有提示的推测。
- 每次最多读取 512 KiB + 4 字节，限制显示行数、长行高亮和图片资源；大文件仍可查看前缀。
- 暗色 / 浅色、换行、行号、原文切换、复制和预览内查找。
- 默认不请求文档中的网络资源，不执行文档自带脚本。
- 可选的只读目录授权：在宿主中选择图片所在目录后，扩展可显示本地图片；宿主不必常驻，支持撤销。
- 安装与自检：系统 Quick Look 样本窗口、当前安装副本的渲染回执，以及可复制的诊断报告。

[类型清单](docs/file-types.md)目前包含 **227 种后缀、86 个格式组、56 个文件名规则**。这些是可识别范围；Finder 是否调用扩展还取决于实际 UTType 和其他已安装的插件。TXT / HTML / PDF / Office 等继续由系统预览，不改变默认打开应用。

2026-11-11 已对全部 **227 种后缀逐一执行 Finder 预览验收**：macOS 27.0.1 / Apple Silicon、0.1.1（12）上，**223 项显示实际内容**（220 项本扩展、3 项系统文本预览），没有未检查项或其他失败。`.ts`、`.mts`、`.edn`、`.exs` 四份文本样本只显示文件信息；按维护者选择保留视频、Adobe 数据和 Logic 音色格式兼容，明确列为限制，不计入内容通过。

详见 [227 项逐行报告](docs/finder-coverage.md)、[机器可读结果](docs/finder-coverage.json)、[明确的兼容边界政策](samples/coverage/accepted-limitations.json) 和 [验收证据规则](docs/finder-coverage-reporting.md)。样本是实际磁盘文件中的代表性语法，不能代替所有文档内容、无后缀文件、dotfile 和其他系统版本的验证。

## 构建

需要 macOS 15+、Xcode 16+、XcodeGen、Python 3，以及 Node 22.13+ 或 24+。当前开发机实际验证为 macOS 27.0.1 / Xcode 27.2 / Apple Silicon；尚未验证其他系统与 Intel。

```sh
./scripts/build
```

开发应用位于 `.build/xcode/Build/Products/Debug/Quicklook.app`。脚本根据单一类型清单生成注册声明，安装锁定的本地 npm 依赖、构建网页资源并生成 Xcode 工程。默认使用仅供本机运行的 ad-hoc 签名，尚未公证或发布。

打开应用，前往“系统设置 → 通用 → 登录项与扩展 → 快速查看”，启用 Quicklook。若安装过同类插件，需要选择实际使用的预览扩展；不应把所有插件同时开启后仍由其他 provider 渲染的结果当作本项目成功。

宿主中的“打开文件”用于直接检查同一套渲染效果。宿主成功不代表 Finder 路由或扩展沙盒权限已通过。

“安装与自检 → 预览示例”将真实文件交给系统 Quick Look。每次检查使用新的样本路径；只有收到当前安装路径、版本、构建号与本次请求一致的扩展渲染回执，才显示验证成功。普通 ad-hoc 构建没有 App Group，需根据实际工具栏与 Finder 结果人工确认。沙盒内无法查询登记状态时显示“无法读取”，不会据此判断扩展已停用。[诊断边界](docs/extension-diagnostics.md)

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

然后在宿主中选择“本地图片访问 → 允许一个文件夹”，至少使用 Space 预览一次其中的 Markdown。扩展会把移交权限转存为自己的持久书签；以后不需要宿主常驻。撤销后关闭并重新打开预览即可生效。

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
- 无扩展名和 dotfile 的内容可识别，但很多文件仍被系统归为 `public.data`。当前未使用宽泛二进制兜底，因此不能保证所有此类文件通过 Space 调用。
- 旧编码的极短样本有歧义；推测结果有提示，不承诺自动识别所有编码。
- PDF / Office 使用系统能力，没有实现办公引擎，也没有承诺完整 Office 版式保真。

## 开源复用

本项目使用 MIT 许可。改编文件保留上游版权，固定来源、修改范围及各依赖许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 和 [渲染器依赖声明](WebRenderer/THIRD_PARTY.md)。运行时许可证随应用资源分发。

产品背景见 [产品调研](docs/product-research-2026-11-10.md)。
