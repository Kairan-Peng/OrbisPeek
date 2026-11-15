# Finder 逐后缀验收证据格式

`scripts/report-finder-coverage.py` 汇总实际 Finder Space 观察，不启动 Finder、不执行 fixture，也不修改应用、扩展注册或系统设置。默认以 `.build/finder-coverage/manifest.json` 中冻结的 227 个后缀为范围，每项都出现在 JSON 和 Markdown 报告中；没有记录的项为 `unknown`。

当前注册表包含 230 个后缀。新批次使用 `.build/finder-coverage-preview-interface`，并显式传入 `--expected-count 230`；同一个预期数量用于清单加载、报告完整性和兼容边界门槛。默认 227 保留历史批次兼容，不改写旧清单、观察或摘要。生成新 fixture 不构成 Finder 验收。

## 保存观察

原始观察保存在被 Git 忽略的 `.build/finder-coverage/observations.jsonl`。每行可保存一条记录，或包含 `observations` 数组的批次；批次共同字段会被每条记录继承。必须使用完整 CUA AX 快照，不使用增量差异、只截取搜索结果或人为构造的 AX 文本。

下例仅说明字段，没有提供实际验收证据：

```json
{
  "caseID": "markdown.md",
  "path": "<manifest中该case的绝对path>",
  "sha256": "<manifest中该case的sha256>",
  "observedAt": "2026-11-11T13:13:44.804Z",
  "evidenceType": "cua-ax",
  "observedFileName": "coverage-markdown.md",
  "provider": {
    "kind": "quicklook",
    "url": "quicklook-app://bundle/index.html"
  },
  "contentObservation": "visible",
  "axText": "<CUA getAXState({disableDiffing:true}) 返回的完整快照>",
  "runMetadata": {
    "macOSVersion": "<实际版本>",
    "osBuild": "<实际系统build>",
    "architecture": "<实际运行架构>",
    "appPath": "/Applications/OrbisPeek.app",
    "appVersion": "<当时安装版本>",
    "appBuild": "<当时安装build>"
  }
}
```

`observedAt` 必须包含时区。`evidenceType` 接受 `cua-ax` 或 `cua-ax+screenshot`；截图可作为补充，但不能省略原始 AX。AX 也可放在独立 UTF-8 文件中，通过 `axFile` 与必填的 `axSHA256` 引用，文件相对路径以 JSONL 所在目录为基准。观察文件和原始 AX 的摘要都进入报告。

系统原生文本预览使用 `provider: {"kind":"system","systemEvidence":"native-text-area"}`。没有直接进程 bundle 证据时，不填写推断的 bundle identifier。无法确认 provider 时使用 `kind: "unknown"`。`x-apple-ql-id2://` 也可能用于第三方数据型预览，不能用它证明系统 provider。

明确看到图标或元数据且未看到正文时，记录 `contentObservation: "missing"` 与具体的 `failureReason`。没有检查正文时使用 `not-checked`，不要把等待超时或一次空快照自动当成内容失败。

## 分类要求

| 结果 | 必须满足的证据 |
|---|---|
| `own-provider-content-pass` | 正确 fixture 路径与 SHA；唯一 Quick Look 窗口；同一个 shell web 区域内有精确文件 Description、`quicklook-app://bundle/index.html`、已知工具栏和正文 marker。兼容历史换行 / 复制 / 查找按钮及旧图标；当前界面使用换行及适用的模式图标，无查找与复制按钮 |
| `system-provider-content-pass` | 正确 fixture 路径与 SHA；唯一 Quick Look 窗口与精确文件标题；正文 marker 位于原生 text area 的实际值；没有 web provider；记录明确的 `native-text-area` 证据 |
| `fail` | 确认正在查看该文件的 Quick Look；实际检查后正文 marker 缺失；记录具体失败原因 |
| `unknown` | 未记录、窗口 / 标题 / 正文 / provider 不完整，或记录的身份、摘要存在歧义 |

脚本限定在同一个 Quick Look 子树内取证，排除另一个 Finder / 编辑器窗口、查找输入框和末尾 focus echo 中的 marker。图标预览的 `QLAXImageAndText_Text` 可以确认所查看的文件名，不能证明正文内容已被预览。

HTML 还必须在受控的 `quicklook-app://bundle/document/<UUID>/content.html` 子文档中显示正文 marker，并有“查看原文, Value: off”的当前渲染模式证据。系统 HTML、外部网页、只有原文回退或只有模式按钮不能通过默认 HTML 渲染验收。工具栏与标题来自 shell，嵌套外部网页不能提供缺失证据。按钮是否实际切换仍需另做功能验收，报告不会据按钮名称推断功能通过。

应用更名为 OrbisPeek 后，预览文档标题使用 `文件名 · OrbisPeek`；脚本仍识别历史记录中的 `文件名 · Quicklook`。内部 provider 标记和资源 URL 保持原名，旧观察的名称、路径与摘要不应改写。

同一 `caseID` 有多条记录时，默认视为有歧义，不自动取最后一次。重测时保留完整原始历史，再明确选择每项的权威观察形成独立最终输入；不要删除原始失败记录。文件、来源清单或 fixture 内容改变后，要先重新确认冻结清单，不能用旧摘要表示新文件。

## 生成与检查报告

```sh
python3 scripts/report-finder-coverage.py \
  --manifest .build/finder-coverage/manifest.json \
  --observations .build/finder-coverage/observations.jsonl \
  --app /Applications/OrbisPeek.app \
  --json-output .build/finder-coverage/results.json \
  --markdown-output .build/finder-coverage/results.md

python3 -m unittest discover -s Tests/Acceptance \
  -p 'test_report_finder_coverage.py' -v
```

多个原始批次文件可同时传给 `--observations`。默认仍应在 `.build` 生成中间结果；最终确认后再明确将输出写到文档目录。默认退出码：`0` 表示全部 case 的实际内容通过且没有输入错误，`1` 表示仍有失败或未知，`2` 表示输入摘要、身份、重复、清单或显式政策验证失败。

`allCasesContentPassed` 表示这些记录覆盖全部内容，不自动证明来自同一构建。`allCasesVerifiedOnSingleRecordedBuild` 还要求每项都有完整的系统、架构、安装路径与版本 / build 元数据，而且这些值一致。`--app` 只记录报告生成时的安装快照，不能倒推出早先观察使用的构建。

`allCasesHaveSameRecordedBuild` 单独表示全部 case 的完整运行元数据一致，与正文是否通过分开判断。`allCasesVerifiedOnSingleRecordedBuild` 同时要求“全部正文通过”和“同一已记录构建”；存在明确批准的兼容限制时，它仍为 `false`，不表示混用了构建。Markdown 中“全部 case 在同一已记录构建与系统上通过”沿用这个严格正文语义；兼容边界结果应查看 `approvedBoundaryGatePassed`。

当前 230 项批次的命令示例（仅在保存实际观察后运行）：

```sh
python3 scripts/report-finder-coverage.py \
  --manifest .build/finder-coverage-preview-interface/manifest.json \
  --expected-count 230 \
  --observations .build/finder-coverage-preview-interface/observations.jsonl \
  --json-output .build/finder-coverage-preview-interface/results.json \
  --markdown-output .build/finder-coverage-preview-interface/results.md
```

## 明确批准的系统格式兼容限制

2026-11-11 用户选择保留以下后缀的原系统格式兼容，将文本正文不能预览作为明确限制。决定保存在版本化的 [accepted-limitations.json](../samples/coverage/accepted-limitations.json) 中，没有通过扩大 UTI 声明接管原格式。

| caseID | 兼容边界 |
|---|---|
| `typescript.ts` | `.ts` 同时用于 MPEG 传输流视频，保留系统视频格式兼容 |
| `typescript.mts` | `.mts` 同时用于 MPEG 传输流视频，保留系统视频格式兼容 |
| `clojure.edn` | `.edn` 可用于 Adobe DRM 元数据，保留 Adobe 格式兼容 |
| `elixir.exs` | `.exs` 可用于 Logic 采样器数据，保留 Logic / GarageBand 格式兼容 |

只有显式追加政策参数时，才评估独立的兼容边界验收：

```sh
python3 scripts/report-finder-coverage.py \
  --manifest .build/finder-coverage/manifest.json \
  --observations .build/finder-coverage/observations.jsonl \
  --app /Applications/OrbisPeek.app \
  --policy samples/coverage/accepted-limitations.json \
  --json-output .build/finder-coverage/results.json \
  --markdown-output .build/finder-coverage/results.md
```

政策必须包含 schema 版本、政策 ID / 版本、明确的用户决定及日期，并为每个 caseID 提供非空理由。未知 case、重复条目、缺少理由、未版本化或未经用户决定的政策会被拒绝。

列入政策不代表自动获准：必须已经实际确认正确文件的 Quick Look 窗口，AX 中确有 `QLAXImageAndText_Text` 和图标、没有 web / native 正文，marker 缺失，且观察明确记为 `missing` 并有失败说明。缺记录、导航未完成、未检查、缺少 AX、身份 / 摘要不符以及其他失败都不接受为限制。

满足时，原始 `status` 仍为 `fail`，增加 `acceptedLimitation: true` 与理由，`allCasesContentPassed` 仍为 `false`。`approvedBoundaryGatePassed` 只有在输入有效、显式预期数量的项全部实际观察、完整运行元数据指向同一构建与系统，而且每项都是正文通过或明确批准的元数据限制时才为 `true`。历史批次默认预期 227 项；新批次传入 230。显式启用政策后，这个独立门槛通过也返回 `0`。

报告同时列出正文通过、已批准限制、其他失败、未知和原始状态，因而可以清楚表达“223 项正文通过、4 项限制、0 项其他失败、0 项未知”，不会写成“227 项正文通过”。这里是预期边界的示例，实际数量始终由保存的观察计算。

公开 JSON / Markdown 只保留相对 fixture 路径、当前 Quick Look 标题 / 正文摘录、原始 AX 摘要和本地证据引用。完整 AX 留在被忽略的原始观察文件中；其他 Finder 标签名、原始 AX 全文和 home 用户名不进入公开报告。外部来源目录会被中性化，仅保留 basename；本地原始文件仍是完整审计来源。

每个 fixture 只是该后缀的小型代表文本。通过结果不代表该格式的全部语法、所有编码 / 文件大小或所有 macOS 版本；本报告也不包含整机重启、跨系统版本或 Intel 实机验证。
