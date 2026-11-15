# Markdown 受控图片标签（1209）

已完成并安装 0.1.1（1209）。Finder 合成文档中的图片与尺寸、原文往返、两种模式的纯文本复制和实际粘贴均通过，查找继续移除。临时图片目录授权已撤销，测试界面已恢复。

## 原因与范围

`README.zh-CN.md` 首行是 `<img src="docs/brand/orbispeek-icon.png" width="96" alt="OrbisPeek 应用图标">`。当前 MarkdownIt 使用 `html: false`，整个标签被转义为正文，`localImages` 为 0；同一相对路径的普通 Markdown 图片会生成请求 token 对应的 `quicklook-resource://` URL。因此问题发生在标签识别阶段。原 PNG 存在，大小 922,600 字节，原图 1024×1024；指定宽度 96 后应按自然比例显示 96×96 CSS px。

本次仅为 Markdown 增加受控 `<img>` 兼容：图片输出复用现有资源链，保留 `src`、`alt` 及有界正整数尺寸。其余 HTML 继续按文字处理；事件、样式、候选图片源等属性不能进入图片输出。代码及注释内的标签保持字面文本。原生目录授权、请求代次、路径、光栅格式与资源预算继续生效。

## 验证边界

自动渲染、实际 WebKit 几何检查与 Finder 扩展验收分别记录。非沙盒 probe 读取成功不能替代 Finder 的图片权限检查。Finder 使用 `.build/validation/markdown-img-1209/fixtures/` 内的合成文档及上述 PNG 副本，不扩大到其他文档目录；测试前本地图片目录授权为空，临时授权应在结束后撤销。

查找继续移除；原文切换、选区纯文本复制及已修复的 Copy 命令入口属于本轮回归范围。

## 实现与自动检查

- 保留 `html: false`，新增独立图片规则，把合法标签转为标准 image token，再由同一图片 renderer 重建输出。没有新增依赖或改变运行时 Swift。
- 属性仅限 `src`、`alt`、1–1600 的正整数 `width/height`，重复属性使用首个值。标签最多 8,192 字符和 64 个属性；畸形输入保守显示文字。
- 仅无高度属性时应用 `height: auto`，使 width-only 保持自然比例、height-only 和双尺寸可生效；图片保留容器宽度约束。
- README 精确输入先 RED 后 GREEN；完整 103 项 JavaScript（原 93 + 新 10）通过，覆盖代码 / 注释 / rawtext / 其他标签属性、实体、重复属性、非法路径、原文与复制等。
- 62 项 Swift（41 Core + 21 UI）通过；实际 WebKit 图片 23 项及原生 Copy 19 项通过。实际几何为 96×96、96×48、height-only 72×72、width-only 84×84；300 CSS px 视口中的可用宽度 264，宽图缩至 264 且无横向溢出。
- 原生 Copy probe 的两种正文均只有 `public.utf8-plain-text`，全部原剪贴板表示精确恢复。独立只读审查通过。

离屏窄窗测试同时调整 probe 的 `preferredContentSize` 并断言实际 viewport，避免仅改变窗口外框却仍以宽视口判断通过。该调整仅在 probe，不进入应用。

## 安装核对

冻结 25 份应用源码 / 网页资源，签名构建与冻结 hash 一致。主 / 扩展 deep/strict 签名、六份网页资源、195 项精确类型及完整 59 份安装文件通过；当前唯一启用扩展来自 `/Applications/OrbisPeek.app`。原运行时 Copy 与控制器文件 hash 保持 1208 的已修复版本。

1208 的 ZIP 备份保存于 `~/Library/Application Support/OrbisPeek/Backups/20261114-104244/OrbisPeek-0.1.1-build1208.zip`，CRC 与两份二进制核对通过；旧 bundle 位于 `~/.Trash/OrbisPeek-0.1.1-build1208-20261114-104244.app`，完整 59 份 hash 与原候选一致。替换脚本在移至废纸篓后清理旧 Launch Services 登记时收到 `-10814`；后续确认旧路径已从登记 dump 消失，完成精确安装路径登记并复核唯一插件，未重置全局缓存或终止 Finder。细节保留在本轮 `registration-recovery-*.json` 与替换记录。

本轮仍为既有 Developer ID / App Group 的 Debug arm64 开发安装，不涉及发布或公证。

## Finder 实际验收

- 未授权时精确 OrbisPeek 主壳显示“本地图片不可读”，证明标签已进入受控加载链。随后只授权合成 `fixtures` 目录。
- 退出宿主后，真实 Finder 显示正确的图标及与 96 CSS px 相符的尺寸；元信息和两个模式 / 换行图标保留，无重复可见文件名、无查找。
- 鼠标拖选含普通文字、粗体和行内代码的段落后 ⌘C，系统剪贴板显示“文本”，内容为 `渲染选区：中文加粗 与 inline_code。`。
- 粘贴到自建普通 TextEdit 富文本文稿后保存，转换回文本与预期逐字符一致且没有粗体格式。该文稿已关闭。
- 原文完整显示 `<img>`、`width="96"`、标题、Markdown 标记及大整数。鼠标从第 1 行拖至第 7 行，选区跨过可见行号和空行；⌘C 后系统剪贴板为“文本”，实际粘贴与原文件对应范围逐字符一致，没有行号和粗体格式。
- 实际点击模式图标完成渲染 → 原文 → 渲染，正确图标恢复；两种视图均只有模式 / 换行图标，无 OrbisPeek 查找栏或复制按钮。通过 Finder 发送 ⌘F 时打开的是 Finder 自身搜索标签，已关闭；不把它写成扩展实体快捷键抑制通过。

初始图片加载和渲染复制使用安装路径 PID 83651；后续预览由安装路径 PID 86309 承载。两次复制后均观察实际 OrbisPeek 正文，未出现扩展失败回退；安装后没有新的本扩展崩溃报告。不以旧 PID 在清理后的退出推断崩溃，也不宣称整轮始终只有同一个 PID。

原文验收曾遇到重开空白，电脑控制工具同时持续返回 `noWindowsAvailable`。用户切回 Finder 后，同一合成文件正常显示并完成原文、复制和模式往返；该现象未再复现。保留空白状态和日志，不据此判定新的解析器问题，也未凭推测修改既有生命周期实现。

## 收尾与证据

七份原样例在安装前、安装后及 UI 操作后的默认打开应用完全一致。25 份应用源码、7 份 renderer 冻结文件、2 份 probe 文件和完整 59 份安装文件在收尾时再次核对一致。临时 `fixtures` 目录授权恢复为空；自建搜索 / 测试标签及两个粘贴文稿均关闭，原 `quicklook` 标签、`README.zh-CN.md` 选区和用户的“资料”标签保留，宿主退出。

本轮本地证据位于 `.build/validation/markdown-img-1209/`：renderer 的 RED/GREEN 与完整测试日志、`markdown-images-probe.json/png`、`native-copy-probe.json`、`swift-tests.log`、三份源码冻结、候选 / 安装检查、`finder-{no-grant,rendered,source,roundtrip}.*`、两次选区 / 剪贴板 / 粘贴记录、`paste-verification.json`、`image-access-{before,granted,revoked}.txt`、`final-audit.json` 和 `acceptance-summary.json`。RTF 文稿也保留在合成目录中，未修改用户文稿。

本轮 Finder 针对一个已知 PNG 与 Markdown 的渲染 / 原文进行实测；height-only、双尺寸及 300px 窄窗的精确几何来自实际 WebKit probe，没有写成 Finder 全格式重新验收。普通用户文档的本地图片仍需在宿主“本地图片访问”中允许其所在文件夹，临时测试授权不会扩大到项目或其他文档目录。

## 用户随后授权真实项目并补验

用户随后明确要求授权当前项目目录。已通过已安装 1209 宿主的原生目录选择器，允许当前项目仓库根目录的只读图片访问；该项目授权按用户要求保留，不再恢复为空。退出宿主后，在 Finder 实际预览真实 `README.zh-CN.md`，主壳、图标及小尺寸显示正常，预览窗口保持打开。同一真实文件的生产 WebKit 测量为 96×96 CSS px，原图 1024×1024，`localImages=1`、`failedImages=0`、`blockedImages=0`。

本次不改源码或重装应用，25 份运行时文件 hash 与 1209 冻结一致。证据单独保存在 `.build/validation/project-readme-1209/`：`authorized-project.txt`、`finder-readme.txt/png`、`readme-webkit.json` 和 `result.json`。这项后续真实项目验证补充前面的合成目录验收，前次临时授权撤销记录仍保留。
