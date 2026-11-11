# Release 构建、打包与回退

本轮交付本地可安装的签名测试包；没有上传公证、发布版本或重启系统。Release 构建和普通 Debug 构建分开存放，不覆盖已安装应用。

用户已明确暂缓公证。本轮所有产物均保持 `notarization=not-submitted`；下文的显式公证入口只作为以后可复用的流程，不在本轮触发，也不继续询问凭据配置。

本机已经跑通 `arm64 + x86_64` 的完整 Release 构建与打包：Developer ID、Hardened Runtime、目录授权、无调试注入和许可证检查通过；ZIP 解包与 DMG 只读挂载后的完整应用文件 hash、可执行文件 hash 和签名均一致。当前包的版本、构建号、体积与 hash 以 `dist/release/` 中的 manifest 为准。

这只证明本地构建与包体验证。安装、真实 Finder 路由和样本自检回执必须另做实际验收；构建阶段不修改 `/Applications` 中已安装的版本，不能将打包成功表述为自检已经通过。

发布 app 的共同签名 / entitlement / 许可证门禁复用 `scripts/validate-installed.py --mode release`；`verify-release` 在此基础上追加 Release 配置、精确架构集合、每个 bundle 的许可证和打包完整性检查。SHA-256 被篡改的 manifest 负对照已正确拒绝。

## 变更与前提

此次发布准备将安装诊断、样本预览和目录授权放入正式优化构建，提供 ZIP、DMG、版本 manifest 与 SHA-256 校验文件。对用户的影响是可用标准应用包安装和更新；运行时不新增服务器或遥测。风险主要是同类 provider 抢占、重复副本注册以及目录授权配置，按中等发布风险对待。

构建需要 Xcode 16+、XcodeGen、Python 3、Node 22.13+ 或 24+，以及本机现有的 Developer ID Application 签名身份。`QUICKLOOK_SIGNING_IDENTITY` 和 `QUICKLOOK_TEAM_ID` 通过环境传入，不写入源码；脚本不创建证书、不修改钥匙串权限，也不读取用户的凭据文件。

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
3. 在 `.build/release-derived/Build/Products/Release/Quicklook.app` 保留可验收构建。
4. ZIP 解包后逐文件比对应用；DMG 只读挂载后验证应用、签名与 `/Applications` 安装快捷方式。
5. 仅在所有检查通过后，把 ZIP、签名 DMG、manifest 和 SHA256SUMS 移入 `dist/release/`。manifest 最后写入，避免把半成品视为已完成发布。

普通构建入口保持兼容：`./scripts/build` 仍为本机 Debug；`--directory-access` 仍启用用户自有签名。新增参数：

```sh
./scripts/build --configuration Release --architectures universal \
  --directory-access --derived-data .build/release-derived --no-register

./scripts/package-release --architectures arm64
./scripts/package-release --app .build/release-derived/Build/Products/Release/Quicklook.app
./scripts/package-release --basic
```

`--basic` 是明确不启用共享目录授权的签名版本。目录授权版本与普通版本的源文件、文档格式和书签存储格式保持兼容；没有数据迁移。Team ID 改变会改变 App Group，不能假设旧目录授权可以跨团队迁移。

### 关于临时登记

Xcode 构建 macOS 应用时会追加 Launch Services 登记。`--no-register` **不是防止瞬时登记的系统开关**；它在构建成功后仅对本次输出 `.app` / `.appex` 的精确路径注销，不改已安装应用或其他 provider。安装验收前应再次确认没有把 `.build` 或 DMG 内的副本当成运行目标。

这个行为核验自 Swift 官方 [ProductPostprocessingTaskProducer](https://github.com/swiftlang/swift-build/blob/9222a8ade22dead4273fa5f10d3550a988e6c094/Sources/SWBTaskConstruction/TaskProducers/OtherTaskProducers/ProductPostprocessingTaskProducer.swift#L653)；没有采用未证实的 `REGISTER_WITH_LAUNCH_SERVICES=NO` 设置。

## 版本与包体验证

```sh
./scripts/verify-release .build/release-derived/Build/Products/Release/Quicklook.app \
  --architectures arm64,x86_64 --json

./scripts/verify-release dist/release/Quicklook-VERSION-macos-universal.manifest.json
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

参考 [Apple 公证文档](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。任何对外分发前应确认 manifest 为 `accepted`、票据装订验证通过，并在目标机器做实际安装验证。

## 安装与本轮验收

1. 退出旧宿主，关闭已有 Quick Look 窗口，保留上一版应用或 ZIP。
2. 将新的 `Quicklook.app` 安装到 `/Applications`，启动宿主并检查安装位置、扩展状态和冲突诊断。
3. 用内置样本通过系统 Quick Look 预览，确认真实 extension 回执；不要把宿主直接渲染当成 Finder 结果。
4. 检查 Markdown、JSON/JSONL、YAML、TOML、properties、INI、日志和源码；TXT / HTML 应继续使用系统预览。
5. 验证本地图片授权、退出宿主后的新 extension 进程恢复、撤销后重新受限。只用项目样本目录，不需要系统重启。
6. 做一次升级和卸载 / 重装验收，检查标准安装路径下唯一的有效副本。其他系统版本与 Intel 的实际运行单列为尚未验证。

放行条件是上述本轮可执行项目有真实结果，未知项明确保留；不会因为包体检查全部通过就宣称所有 Finder 路由或重启恢复已验证。

## 回退

安装前保留当前应用的可恢复副本。遇到无法预览、扩展无法启动或明显延迟时，退出宿主、关闭预览，将旧应用恢复到原安装路径；只重登记恢复后的本项目扩展，不全局重置文件关联，不删除其他 provider。

当前无数据库或文档迁移，回退不需要改写用户文件。目录授权共享列表仍为 v1；若团队 / App Group 不同，使用宿主重新选择目录。卸载默认保留设置和授权缓存；需要清除授权时先在宿主撤销，避免把清理偏好设置作为修复预览的默认动作。

回退后核对应用版本、签名、唯一安装路径，并实际 Space 预览核心样本。检查失败时保留本地诊断，停止继续覆盖安装。

## 发布后观察与故障定位

首先观察安装 / 启用失败、实际 provider 回执缺失、预览加载错误、图片受限和大文件首屏延迟。默认只使用本地诊断与用户主动反馈，不增加后台上传或常驻轮询。

- 启用后仍没有本项目预览：检查登记是否指向 `/Applications`，排查重复副本和同类插件。
- extension 一直转圈：先跑签名 / entitlement 验证，核对没有 `get-task-allow`，再看本项目进程日志。
- 只有图片失败：检查所选目录、当前授权 ID 和 App Group，不扩大到全盘访问。
- 某个后缀失败：用类型探针查看真实 UTType；不要用抢占媒体或系统文本类型来掩盖冲突。

快速缓解是恢复上一版或在系统设置中临时停用本项目扩展；不会重启系统、关闭系统安全机制或批量终止 Finder。定位入口分别是宿主诊断、共享渲染组件和 `DirectoryAccess`，各项本地报告应先由用户检查再对外分享。
