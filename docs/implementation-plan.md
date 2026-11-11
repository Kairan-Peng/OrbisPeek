# 首版实现与验证计划

本轮目标：可构建的现代 macOS Quick Look 扩展，共用宿主与扩展的渲染组件，优先支持 Markdown、JSON/JSONL、YAML、TOML、properties、INI、日志与常用源码，并用真实文件验证类型路由、本地图片、编码和大文件。

1. 固定上游版本，选择性复用 FreeLook / QLStephenSwift；保留 MIT 许可与来源。
2. 将类型清单设为单一数据源，生成注册声明与文档；不接管 TXT / HTML / PDF / Office，不把视频 UTI 认作 TypeScript。
3. 构建有界文本读取和统一的 Markdown / 高亮 / JSON / JSONL 渲染；不携带 Node runtime。
4. 使用 SwiftPM 测试核心边界，用真实 WKWebView 渲染检查输出与图片策略，再构建宿主和 `.appex`。
5. 安装本地开发构建，记录实际 provider 与文件路由；明确失败或环境限制，不把类型识别数量当成 Finder 成功率。
6. 根据证据修正实现，补构建说明、许可证、样本和验证结果；不创建分支、提交或发布。

当前版本的本地图片策略只允许文档目录内的光栅图片，限制文件大小与像素数，并拒绝目录遍历 / 符号链接越界。扩展能否读取同目录文件必须在沙盒内实际验证；宿主中的成功不能代替扩展证据。
