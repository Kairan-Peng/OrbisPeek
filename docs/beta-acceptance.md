# 0.1 测试版：安装与无需系统重启的验收

本轮明确不进行系统重启、注销或跨版本系统升级。用真实 Finder Space、应用退出和扩展进程重新启动检查日常流程；进程重启的结果不能代替整机重启后的权限恢复。

## 首次使用样本

`OnboardingSamples.prepare()` 将应用内的五个资源导出到当前宿主沙盒的 `Caches/OrbisPeek Preview Samples/v1`，返回四份文档的文件系统 URL。PNG 与 Markdown 同目录，作为相对图片资源。已有内容完全一致时复用；已有样本被编辑、删除或被改成符号链接时，创建新的随机子目录，不覆盖原来的内容。

显式自检应调用 `OnboardingSamples.prepare(freshForVerification: true)`：每次将同样的四份文档和 PNG 复制到新的 `v1-check-UUID` 子目录，让文件 URL 随本次检查变化，规避系统按原 URL 复用旧预览。默认 `prepare()` 保留稳定复用语义。新 URL 本身仍不是扩展执行成功的证据，必须收到本次自有扩展回执后再标记验证通过；已有样本目录不自动删除，以免丢失用户修改。

素材改写自本项目的 `samples/fixtures/`；棋盘 PNG 是首次原型中用 Python 标准库生成的样本。没有下载外部图片，也没有网络资源或可执行脚本。

| 文件 | 验收内容 |
|---|---|
| `orbispeek-sample.md` | 标题、任务列表、表格、代码块；顶部本项目工具栏；原文切换与正文复制 |
| `orbispeek-sample.png` | 160 × 96 蓝色 / 米色棋盘；未授权目录时提示受限，授权后在 Markdown 中显示 |
| `orbispeek-sample.json` | 格式化后保留完整大整数、两个同名键和中文；原文切换不改写源文件 |
| `orbispeek-sample.jsonl` | 三条记录中故意包含一条坏行，最后一条中文记录仍可读 |
| `orbispeek-sample.toml` | 保留注释、section、数组、中文及 emoji |

宿主里的自有渲染组件显示成功，只说明渲染链可用。“预览样本”应将导出的真实 URL 交给系统 Quick Look 或 Finder，并由本项目扩展的运行回执 / 实际界面确认 provider。Markdown 正文排版也可能由其他插件完成，因此单看标题、表格或图片不能证明本项目已被调用。

最终实现使用内嵌的系统 `QLPreviewView` 和一次性回执。Finder 验收另用普通可访问目录中的项目样本或自己的文档；本机 Finder 预览宿主缓存容器里的同内容样本曾转圈，因此不提供直接揭示该缓存样本的入口。实际结果见 [本轮验收记录](beta-validation-2026-11-11.md)。

## 只读安装检查

```sh
python3 scripts/validate-installed.py /Applications/OrbisPeek.app \
  --mode release --require-installed --require-registered \
  --expect-arch arm64 --expect-arch x86_64 \
  --output .build/validation/installed-release.json

# 按实际版本与构建号检查升级后的同一个安装路径。
python3 scripts/validate-installed.py /Applications/OrbisPeek.app \
  --mode release --expect-version 0.1.1 --expect-build 10 \
  --require-registered --output .build/validation/after-upgrade.json

# 在人工移除这个精确路径后检查文件与注册证据。
python3 scripts/validate-installed.py /Applications/OrbisPeek.app \
  --mode absent --output .build/validation/after-uninstall.json
```

实际安装在 `~/Applications` 时替换路径。`--expect-version` 和 `--expect-build` 使用本轮产物的真实值；示例数值不是已通过的版本声明。

该脚本只读取目标应用、签名、架构、许可证和本项目的 `pluginkit` 注册信息；输出 JSON，必需检查失败或无法确定时返回非零。它不会安装、删除、修改 election、修复 Launch Services、请求图片权限、扫描用户文档、公证或重启。

- `development` 模式接受有效的本地开发签名，将 Debug 注入库和非标准安装目录列为警告。
- `release` 模式要求 Developer ID、hardened runtime、无 `get-task-allow` 与 Debug 注入库；检查宿主 / 扩展版本、签名团队和 App Group 一致性。
- `--require-registered` 要求该精确应用路径中存在本项目的已注册扩展。它不等于启用，也不等于 Finder 已调用。
- `--require-enabled` 仅接受本项目该路径明确的 `+` / `use` election；默认 election 保持为默认证据，不伪称已启用或被选中。
- `absent` 只验证指定路径及其中的扩展已经不再可加载；另一个开发构建仍存在时会列为警告。需要检查全部已注册副本时追加 `--require-no-copies`。
- 过期的注册路径、工具不可用和解析失败要与“没有扩展”区分。公证状态保持未知，由发布流水线另行验证；本脚本不做联网 Gatekeeper 检查。

## 验收矩阵

| 阶段 | 操作与应保留证据 | 通过条件 |
|---|---|---|
| 清理冲突 | 记录 QLMarkdown / Syntax Highlight 等专用插件的原路径与注册状态；仅按本轮用户授权移走对应宿主应用，保留可恢复副本 | 指定第三方插件不再注册到原安装路径；Apple、Xcode、GarageBand 等宿主不因含有 Quick Look 扩展而被删除 |
| 新安装 | 从发布产物安装到 `/Applications` 或 `~/Applications`，不从 DMG、下载缓存或 `.build` 运行；保留 `validate-installed.py` 报告 | 应用、嵌入扩展、签名、许可证、版本和实际安装路径正确；状态检测清楚显示是否仍需启用 |
| 首次预览 | 在宿主点击样本按钮；对 MD / JSON / JSONL / TOML 观察真实系统预览，并记录自有扩展回执与界面 | 确认为当前安装路径的本项目扩展，格式内容与上表一致；未回执时显示尚未确认，而不是成功 |
| 宿主退出 | 退出宿主，在 Finder 选中普通目录中的样本按 Space；必要时仅终止本项目扩展让系统启动新进程 | 无需宿主常驻，文本仍可读；这不是系统重启测试 |
| 图片授权 | 在宿主选择普通目录中的测试样本文件夹；Space 预览 Markdown；退出宿主并重新启动扩展后再预览 | 图片显示，文字与权限提示正确；不请求根目录、完全磁盘访问或网络图片 |
| 撤销 | 宿主撤销样本目录授权，关闭现有预览；启动新的扩展预览同一 Markdown | 本地图片重新受限，原文继续可读；保留的私有书签缓存不能绕过共享授权列表 |
| 升级 | 同一 bundle identifier、安装路径和签名身份，用更大的 build 号替换旧应用；记录前后版本、签名、注册路径、回执 | 新版本实际被调用；不再从旧 `.build`、旧 DMG 或备份路径加载；用户已有样本修改不被覆盖 |
| 卸载 | 人工移除本轮安装的精确 `OrbisPeek.app`；不顺手删除用户样本或偏好；保留 absent 报告 | 指定路径已不存在，无存活扩展从该路径加载；TXT / HTML 仍可使用系统 Space 预览 |
| 回退 / 重装 | 重新放回上一个已验证的签名产物或本轮 Release；检查路径、签名、回执 | 能恢复文本预览；图片权限如失效应明确提示重新选择目录，不扩大授权 |

## 本轮记录边界

脚本报告与界面回执由主集成执行后记录在 `.build/validation/`。本文是验收方案，不把矩阵条目自动视作已经通过。尚未执行的系统版本、Intel 实机、整机重启与公证分发，继续标为未验证。

逐后缀的真实 Finder 观察使用独立的 [证据格式与汇总流程](finder-coverage-reporting.md)：冻结 fixture 清单，保存完整 CUA AX JSONL，按正文 marker、准确文件标题和实际 provider 分别统计自有 / 系统内容通过、失败与未知。未记录项不计通过，原始 AX 不放入公开文档。

主要故障定位顺序：安装路径和嵌入扩展 → 注册 / election → 竞争 provider → 自有扩展回执 → 文件 UTType → 渲染错误。图片问题另检查目录授权；不要用全盘 exception 或清空全部系统缓存掩盖原因。
