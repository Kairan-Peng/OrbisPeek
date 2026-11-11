# 最小原型验证方案

本方案将内容读取、Web 渲染和 Finder 路由分开记录，避免用宿主预览或 UTType 声明代替真实的 Space 扩展验证。样本由 Python 标准库生成，不执行其中任何源码。

## 1. 可复现样本

```sh
python3 scripts/make-fixtures.py
```

小样本位于 `samples/fixtures/`。脚本每次校验预期内容，缺失时创建；已经存在但内容不同时报错，不覆盖用户或其他任务写入的文件。`manifest.json` 记录 SHA-256、编码、字节数及预期行为。

覆盖范围：

- Markdown：GFM、中文、代码块、表格、任务列表，以及正常图片、带空格路径、远程资源、父目录路径、符号链接越界、SVG、原始脚本。
- JSON / JSONL：正常对象、大整数、重复键、语法错误、空行、坏行后的有效记录、脚本字符串；JSONC / JSON5 按源码高亮。
- YAML、TOML、properties、INI、conf / cfg、日志、长行、零字节文件。
- 无扩展名 `README`、`Dockerfile`、`Makefile`，以及 `.env` / `.gitignore` / `.zshrc`。
- 常用源码：Swift、Python、JavaScript / TypeScript / TSX、Go、Rust、Java、C / C++、SQL、Shell、CSS、diff。
- UTF-8 / BOM、UTF-16 LE/BE（有 / 无 BOM）、GB18030（短 / 中 / 长，含四字节字符）、GBK、Big5、Shift-JIS。
- 二进制伪装成 `.log`、损坏的 UTF-16，以及保留系统预览的 `.txt` / `.html`。

旧编码的极短输入本身有歧义。自动推测警告是必要的，不能因为字符串能解码或字符数相同就认定编码准确；核心单元测试另外对真实旧编码样本做原文相等断言。

## 2. 内容读取与大文件

先构建 probe，再批量检查小样本：

```sh
swift build --product quicklook-probe
python3 scripts/make-fixtures.py --inspect
```

可用 `--probe /absolute/path/quicklook-probe` 指定其他构建产物。报告默认为 `.build/validation/fixture-inspect.json`，记录每个文件的模式、语言、系统解析的 UTType、编码、读取字节、总大小、截断、耗时和错误。

批量检查会验证读取预算、文件大小、预期拒绝、模式与字符数等结构性结果。它不启动真实的 Finder provider，也不能证明格式化后的文字和图片正确。

大文件需明确选择生成，默认不进入样本目录：

```sh
python3 scripts/make-fixtures.py --large --inspect
/usr/bin/time -l .build/debug/quicklook-probe inspect .build/fixtures/repeated-100MiB.log .build/fixtures/sparse-prefix-1GiB.jsonl
```

- `repeated-100MiB.log` 是完整重复生成的 UTF-8 文本，准确大小为 100 MiB。
- `sparse-prefix-1GiB.jsonl` 的前 1 MiB 多为完整 UTF-8 JSONL 记录，随后为稀疏零填充；准确逻辑大小为 1 GiB。它只证明预览器有界读取真实文本前缀，**不能当作完整有效 1 GiB JSONL 的解析基准**。
- 两者都只应读取 524,288 + 至多 4 字节，返回 `truncated=true`，文件大小不得触发全量读取。
- 首次加载与重复加载耗时分开保存。`time -l` 的 probe 常驻集不等于扩展 + WebContent 的总内存；两者应分别测量。

2026-11-10 在当前 macOS 27 开发机的一次读取验证：58 个小样本和 2 个大样本均通过结构性检查；100 MiB / 1 GiB 输入分别只读取 524,292 字节，耗时约 43 ms / 36 ms，合计执行进程最大常驻集约 19.1 MB。这些是本次 `inspect` 的文件读取 / 解码数据，**不代表 Quick Look 首屏时间、WebContent 总内存或 p95**。旧编码样本的解码字符数符合预期；GBK 被标为其超集 GB18030，旧编码均有推测警告。完整原文相等由核心单元测试另外覆盖。

## 3. Web 渲染与资源边界

```sh
.build/debug/quicklook-probe render samples/fixtures/markdown/basic.md --output .build/validation/markdown.json --snapshot .build/validation/markdown.png
.build/debug/quicklook-probe render samples/fixtures/markdown/resources.md --output .build/validation/resources.json --snapshot .build/validation/resources.png
.build/debug/quicklook-probe render samples/fixtures/data/large-integer-duplicate-keys.json --output .build/validation/json.json
.build/debug/quicklook-probe render samples/fixtures/data/bad-middle-row.jsonl --output .build/validation/jsonl.json
```

截图前需确认输出目录存在。期望：

| 输入 | 通过条件 |
|---|---|
| 基础 Markdown | 表格 / 任务列表 / 高亮正确，中文可读，子目录 PNG 可见 |
| 资源边界 | 只允许两幅目录内光栅图片；远程、父目录、符号链接越界、文件 URL 和 SVG 不加载 |
| 文档脚本 | 标题不出现 `UNSAFE_SCRIPT_EXECUTED`，脚本不会修改全局变量或触发请求 |
| 大整数 / 重复键 | 每一位数字与两个重复键都保留，原文和格式化视图一致 |
| 坏 JSON | 原文保留，显示明确的解析错误而非空白预览 |
| 坏 JSONL | 坏行可定位，后面的有效行仍可阅读，空行不破坏源行号 |
| 长行 | 换行切换与窄窗口可用，控制栏不被超宽内容挤出 |

`render` probe 是宿主进程中的 WKWebView 验证。图片在这里加载成功，只能证明资源策略与渲染链正常；还必须在沙盒 extension 中重复验证权限。

## 4. 真实 Finder / Space 路由

安装本地构建后，对格式族逐项记录：系统版本、文件路径、实际 UTType、实际 provider、可见预览、资源受限信息。至少覆盖 Markdown、JSON、JSONL、YAML、TOML、properties、INI、log、常用源码、无扩展名及 dotfile。

需要区分：

1. 注册清单声称支持。
2. 文件解析成清单中的 UTType。
3. Quick Look 真正调用该扩展。
4. 扩展成功呈现文本与本地资源。

只有第 4 项通过才能记录为真实预览通过。`inspect` 能完成的是第 2 项相关证据；`qlmanage` 注册输出也不能单独证明第 4 项。

TXT、HTML、PDF、Office 安装前后使用系统 provider，不能为了增加覆盖数抢占它们。TypeScript `.ts` 与媒体传输流冲突、已有同类插件的竞争、文件关联变化都要单独记录，不将某一台机器的结果推广为所有系统结论。

目前开发机为 macOS 27；macOS 15 / 26 需另外的真实测试环境。没有对应环境时应保留未验证标记。
