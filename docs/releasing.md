# Release 构建、打包与回退

本指南记录签名构建、打包与验收流程。Release 构建和普通 Debug 构建分开存放，不自动覆盖已安装应用。当前 0.1.1（1227）提供未公证预览安装包，用户步骤见[安装说明](installing.md)。

当前发行明确不提交公证，产物保持 `notarization=not-submitted`；下文的显式公证入口只作为以后可复用的流程，不在本轮触发。

本机已经跑通 `arm64 + x86_64` 的完整 Release 构建与打包：Developer ID、Hardened Runtime、目录授权、无调试注入和许可证检查通过；ZIP 解包与 DMG 只读挂载后的完整应用文件 hash、可执行文件 hash 和签名均一致。当前包的版本、构建号、体积与 hash 以 `dist/release/` 中的 manifest 为准。

这只证明本地构建与包体验证。安装、真实 Finder 路由和样本正文显示必须另做实际验收；构建阶段不修改 `/Applications` 中已安装的版本，不能将打包成功表述为 Finder 验收已经通过。

发布 app 的共同签名 / entitlement / 许可证门禁复用 `scripts/validate-installed.py --mode release`；`verify-release` 在此基础上追加 Release 配置、精确架构集合、每个 bundle 的许可证和打包完整性检查。SHA-256 被篡改的 manifest 负对照已正确拒绝。

## 变更与前提

发布构建提供 Quick Look 预览扩展、精简宿主的介绍与目录管理，以及默认关闭的无后缀文本预览开关，并生成 ZIP、DMG、版本 manifest 与 SHA-256 校验文件。宿主不再提供安装诊断、内置样本自检或独立文档打开入口；开发验证工具仍保留。对用户的影响是可用标准应用包安装和更新；运行时不新增服务器或遥测。风险主要是同类 provider 抢占、重复副本注册以及目录授权配置，按中等发布风险对待。

构建需要 Xcode 16+、XcodeGen、Python 3.11+、Node 24，以及本机现有的 Developer ID Application 签名身份。`QUICKLOOK_SIGNING_IDENTITY` 和 `QUICKLOOK_TEAM_ID` 通过环境传入，不写入源码；脚本不创建证书、不修改钥匙串权限，也不读取用户的凭据文件。

目标最低 macOS 15；Universal 表示两种 Mach-O 架构都编译、签名并通过包体检查，不表示已经在 Intel 或每个 macOS 版本运行。无系统重启属于本轮明确限制。

## 构建与打包

```sh
export QUICKLOOK_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export QUICKLOOK_TEAM_ID='TEAMID'
./scripts/package-release
```

默认流程：

1. 由锁定的 npm 依赖重建网页资源和第三方声明，生成文件类型声明与 Xcode 工程。
2. 构建 `Release`、`arm64 x86_64`、App Sandbox、Hardened Runtime 和可选目录授权。禁用 debug dylib 与 `get-task-allow`。
3. 在 `.build/release-derived/Build/Products/Release/OrbisPeek.app` 保留可验收构建。
4. ZIP 解包后逐文件比对应用；DMG 只读挂载后验证应用、签名与 `/Applications` 安装快捷方式。
5. 仅在所有检查通过后，把 ZIP、签名 DMG、manifest 和 SHA256SUMS 移入 `dist/release/`。manifest 最后写入，避免把半成品视为已完成发布。

普通构建入口保持兼容：`./scripts/build` 仍为本机 Debug；`--directory-access` 仍启用用户自有签名。新增参数：

```sh
./scripts/build --configuration Release --architectures universal \
  --directory-access --derived-data .build/release-derived --no-register

./scripts/package-release --architectures arm64
./scripts/package-release --app .build/release-derived/Build/Products/Release/OrbisPeek.app
./scripts/package-release --basic
```

`--basic` 是明确不启用共享目录授权的签名版本；没有 App Group 配置时，无后缀文本预览开关也不可用。目录授权版本与普通版本的源文件、文档格式和书签存储格式保持兼容；没有数据迁移。Team ID 改变会改变 App Group，不能假设旧目录授权可以跨团队迁移。

### 关于临时登记

Xcode 构建 macOS 应用时会追加 Launch Services 登记。`--no-register` **不是防止瞬时登记的系统开关**；它在构建成功后仅对本次输出 `.app` / `.appex` 的精确路径注销，不改已安装应用或其他 provider。安装验收前应再次确认没有把 `.build` 或 DMG 内的副本当成运行目标。

这个行为核验自 Swift 官方 [ProductPostprocessingTaskProducer](https://github.com/swiftlang/swift-build/blob/9222a8ade22dead4273fa5f10d3550a988e6c094/Sources/SWBTaskConstruction/TaskProducers/OtherTaskProducers/ProductPostprocessingTaskProducer.swift#L653)；没有采用未证实的 `REGISTER_WITH_LAUNCH_SERVICES=NO` 设置。

## 版本与包体验证

```sh
./scripts/verify-release .build/release-derived/Build/Products/Release/OrbisPeek.app \
  --architectures arm64,x86_64 --json

./scripts/verify-release dist/release/OrbisPeek-VERSION-macos-universal.manifest.json
```

验证覆盖：

- 宿主和 extension 都声明 `Release`，版本号、构建号、签名团队及架构集合一致。
- Developer ID、Hardened Runtime、App Sandbox、正确 App Group 与 bookmark entitlement；没有调试注入或全盘临时读取例外。
- 宿主和 extension 均带完整的本项目及运行时依赖许可证。
- ZIP / DMG 的字节数、SHA-256、应用文件树和两份可执行文件 hash 与 manifest 一致。
- DMG 安装快捷方式存在，挂载检查结束后卸载测试卷。

SHA-256 用于检查下载完整性；不能单独证明某个下载源可信。默认 manifest 的公证状态是 `not-submitted`，验签通过不能被表述为已通过 Gatekeeper 分发验收。

对 `not-submitted` 包的检查不进行在线公证评估。对明确标为 `accepted` 的 manifest，验证会调用 Apple 的 `stapler validate` 与 Gatekeeper 检查；`stapler validate` 会联系票据服务核对最新票据，需要网络。

## 可选：明确提交 Apple 公证

只有下列显式选项会上传包体；常规构建与打包不会上传：

```sh
./scripts/package-release --notarize-profile YOUR_EXISTING_KEYCHAIN_PROFILE
```

该命令使用已存在的 notarytool 钥匙串 profile，构建时请求安全时间戳，将 ZIP 与 DMG 提交 Apple；只有 `Accepted` 才会继续装订和重建校验信息。没有在本轮执行此选项，也没有探测或创建 profile。公证失败则保留失败，不生成伪装为通过的发布 manifest。

参考 [Apple 公证文档](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。面向普通用户的正式广泛分发应先完成公证、确认 manifest 为 `accepted`、票据装订验证通过，并在目标机器做实际安装验证。维护者明确授权的未公证预览发行可以保持 `not-submitted`，但发布页与安装说明必须醒目标注未公证、首次打开可能受阻及实际验证边界；不能改写为 `accepted`，也不以签名或包体校验代替 Gatekeeper 验收。当前 0.1.1（1227）采用这一预览发行方式，不上传公证；用户步骤见[安装说明](installing.md)。

## 安装与本轮验收

1. 退出旧宿主，关闭已有 Quick Look 窗口，保留上一版应用或 ZIP。
2. 将新的 `OrbisPeek.app` 安装到 `/Applications`，启动宿主，并在“系统设置 → 通用 → 登录项与扩展 → 快速查看”检查启用状态。用 `scripts/validate-installed.py --mode release` 核对安装包、签名与 entitlement，再用 `pluginkit` 检查唯一启用副本及其路径；这些检查不能代替实际正文验收。
3. 在 Finder 选中 `samples/fixtures/` 或新建合成目录中的已知样本，按 Space，确认本项目工具栏和样本正文实际出现。结合本扩展进程路径核对 provider；不能将系统图标 / 文件信息或独立 WebKit probe 当成 Finder 正文成功。宿主不再提供内置样本自检入口。
4. 检查 Markdown、JSON/JSONL、YAML、TOML、properties、INI、日志和源码；HTML/HTM/XHTML、TXT / PDF / Office 应继续使用系统预览。当前版本无查找、“打开方式 → OrbisPeek”或“打开文件… / ⌘O”入口。选区复制按[当前验证方案](validation-plan.md)另行核对。
5. 验证本地图片授权、退出宿主后的新 extension 进程恢复、撤销后重新受限。只用项目样本目录，不需要系统重启。
6. 共享配置版本另测无后缀文本预览开关：默认关闭，明确开启后才尝试实际类型直接为 `public.data` 的文本；更改后关闭并重新打开预览，检查文本显示、二进制拒绝、关闭后恢复系统图标 / 信息及宿主重开后的状态保留。任意陌生动态后缀仍不保证接管，具体边界见[开关验收](extensionless-opt-in-validation-2026-11-15.md)。
7. 做一次升级和卸载 / 重装验收，检查标准安装路径下唯一的有效副本。其他系统版本与 Intel 的实际运行单列为尚未验证。

从原名 Quicklook 的版本升级时，安装包现在使用 `OrbisPeek.app`，但 bundle identifier、设置键和 App Group 保持不变。先退出旧宿主，将旧 `Quicklook.app` 保存到正式安装目录之外的备份位置，再安装新名称的应用；避免两份同一身份的应用同时作为预览候选。历史验收报告中的旧名称和路径保留原样，不代表新构建已经完成同一轮验收。

放行条件是上述本轮可执行项目有真实结果，未知项明确保留；不会因为包体检查全部通过就宣称所有 Finder 路由或重启恢复已验证。

## 回退

安装前保留当前应用的可恢复副本。遇到无法预览、扩展无法启动或明显延迟时，退出宿主、关闭预览，将旧应用恢复到原安装路径；只重登记恢复后的本项目扩展，不全局重置文件关联，不删除其他 provider。

当前无数据库或文档迁移，回退不需要改写用户文件。目录授权共享列表仍为 v1；若团队 / App Group 不同，使用宿主重新选择目录。卸载默认保留设置和授权缓存；需要清除授权时先在宿主撤销，避免把清理偏好设置作为修复预览的默认动作。

回退后核对应用版本、签名、唯一安装路径，并实际 Space 预览核心样本。检查失败时保留本地诊断，停止继续覆盖安装。

## 发布后观察与故障定位

首先观察安装 / 启用失败、实际 provider 与预期不符、样本正文缺失、预览加载错误、图片受限和大文件首屏延迟。默认只使用本地验证工具、进程日志与用户主动反馈，不增加后台上传或常驻轮询。

- 启用后仍没有本项目预览：检查登记是否指向 `/Applications`，排查重复副本和同类插件。
- extension 一直转圈：先跑签名 / entitlement 验证，核对没有 `get-task-allow`，再看本项目进程日志。
- 只有图片失败：检查所选目录、当前授权 ID 和 App Group，不扩大到全盘访问。
- 某个后缀失败：用类型探针查看真实 UTType；不要用抢占媒体或系统文本类型来掩盖冲突。

快速缓解是恢复上一版或在系统设置中临时停用本项目扩展；不会重启系统、关闭系统安全机制或批量终止 Finder。定位入口是 `scripts/validate-installed.py`、`pluginkit`、本扩展进程日志、共享渲染组件和 `DirectoryAccess`；宿主仅提供目录管理与可选文本预览设置，各项本地报告应先由用户检查再对外分享。
