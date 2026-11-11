# Finder 逐后缀真实预览验收

生成时间：2026-11-11T14:17:57.040172+00:00。本报告只根据保存的 CUA 原始 AX 证据分类，不使用 UTType 命中率代替预览结果。

输入校验：通过。全部内容通过：否。

已批准兼容边界验收：通过。兼容限制继续保留原始 fail 状态，不计为正文内容通过。

| 验收结果 | 数量 |
|---|---:|
| 正文内容通过 | 223 |
| 明确批准的兼容限制 | 4 |
| 其他内容失败 | 0 |
| 未知 | 0 |

| 分类 | 数量 |
|---|---:|
| own-provider-content-pass | 220 |
| system-provider-content-pass | 3 |
| fail | 4 |
| unknown | 0 |
| 总 case | 227 |
| 缺少观察记录 | 0 |

## 运行与证据

报告机器快照：{"platform": "macOS-27.0.1-arm64-arm-64bit-Mach-O", "macOSVersion": "27.0.1", "architecture": "arm64", "osBuild": "26A434"}。
报告时安装快照：{"path": "/Applications/Quicklook.app", "evidence": "report-time bundle snapshot, not per-observation provenance", "bundleIdentifier": "org.quicklook.preview", "version": "0.1.1", "build": "12", "executableSHA256": "a0f020337f8dfb53327c6321a5a025c1ed40cbbbd37c45030b93dde8d61556cb"}。
逐批记录的版本 / build：[{"version": "0.1.1", "build": "12", "recordCount": 227}]。
显式兼容边界政策：preserve-system-format-compatibility / 1.0.0；决定日期 2026-11-11；来源 samples/coverage/accepted-limitations.json；SHA-256 b9142e62b3aeb29394882e22eeb7b7274575220ca5cb4d010d27aca364e5f5c5。
安装快照不自动证明早先每条观察使用相同构建。机器、安装信息如记录在各批 runMetadata 中，以各条原始记录为准。

具备完整运行元数据的 case：227 / 227。全部 case 在同一已记录构建与系统上通过：否。

## 逐项结果

| # | 后缀 | 格式组 | 原始结果 | 已批准兼容限制 | 文件 | 原因 |
|---:|---|---|---|---|---|---|
| 1 | .md | markdown | own-provider-content-pass | — | coverage-markdown.md | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 2 | .markdown | markdown | own-provider-content-pass | — | coverage-markdown.markdown | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 3 | .mdown | markdown | own-provider-content-pass | — | coverage-markdown.mdown | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 4 | .mkd | markdown | own-provider-content-pass | — | coverage-markdown.mkd | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 5 | .mkdn | markdown | own-provider-content-pass | — | coverage-markdown.mkdn | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 6 | .mdwn | markdown | own-provider-content-pass | — | coverage-markdown.mdwn | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 7 | .mdtxt | markdown | own-provider-content-pass | — | coverage-markdown.mdtxt | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 8 | .mdtext | markdown | own-provider-content-pass | — | coverage-markdown.mdtext | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 9 | .json | json | own-provider-content-pass | — | coverage-json.json | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 10 | .webmanifest | json | own-provider-content-pass | — | coverage-json.webmanifest | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 11 | .jsonl | json-lines | own-provider-content-pass | — | coverage-json-lines.jsonl | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 12 | .ndjson | json-lines | own-provider-content-pass | — | coverage-json-lines.ndjson | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 13 | .jsonc | json-with-comments | own-provider-content-pass | — | coverage-json-with-comments.jsonc | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 14 | .code-workspace | json-with-comments | own-provider-content-pass | — | coverage-json-with-comments.code-workspace | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 15 | .json5 | json5 | own-provider-content-pass | — | coverage-json5.json5 | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 16 | .yaml | yaml | own-provider-content-pass | — | coverage-yaml.yaml | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 17 | .yml | yaml | own-provider-content-pass | — | coverage-yaml.yml | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 18 | .toml | toml | own-provider-content-pass | — | coverage-toml.toml | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 19 | .properties | properties | own-provider-content-pass | — | coverage-properties.properties | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 20 | .ini | ini | own-provider-content-pass | — | coverage-ini.ini | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 21 | .cfg | ini | own-provider-content-pass | — | coverage-ini.cfg | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 22 | .conf | ini | system-provider-content-pass | — | coverage-ini.conf | Correct title and marker in a native text area; no web provider is present |
| 23 | .cnf | ini | own-provider-content-pass | — | coverage-ini.cnf | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 24 | .config | ini | own-provider-content-pass | — | coverage-ini.config | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 25 | .desktop | ini | own-provider-content-pass | — | coverage-ini.desktop | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 26 | .log | logs | own-provider-content-pass | — | coverage-logs.log | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 27 | .out | logs | own-provider-content-pass | — | coverage-logs.out | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 28 | .err | logs | own-provider-content-pass | — | coverage-logs.err | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 29 | .lock | plain-config | own-provider-content-pass | — | coverage-plain-config.lock | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 30 | .gitignore | plain-config | own-provider-content-pass | — | coverage-plain-config.gitignore | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 31 | .gitattributes | plain-config | own-provider-content-pass | — | coverage-plain-config.gitattributes | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 32 | .gitmodules | plain-config | own-provider-content-pass | — | coverage-plain-config.gitmodules | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 33 | .env | dotenv | own-provider-content-pass | — | coverage-dotenv.env | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 34 | .gitconfig | git-config | own-provider-content-pass | — | coverage-git-config.gitconfig | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 35 | .editorconfig | git-config | own-provider-content-pass | — | coverage-git-config.editorconfig | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 36 | .npmrc | git-config | own-provider-content-pass | — | coverage-git-config.npmrc | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 37 | .yarnrc | git-config | own-provider-content-pass | — | coverage-git-config.yarnrc | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 38 | .swift | swift | own-provider-content-pass | — | coverage-swift.swift | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 39 | .swiftinterface | swift | own-provider-content-pass | — | coverage-swift.swiftinterface | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 40 | .js | javascript | own-provider-content-pass | — | coverage-javascript.js | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 41 | .mjs | javascript | own-provider-content-pass | — | coverage-javascript.mjs | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 42 | .cjs | javascript | own-provider-content-pass | — | coverage-javascript.cjs | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 43 | .jsx | javascript | own-provider-content-pass | — | coverage-javascript.jsx | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 44 | .ts | typescript | fail | .ts 同时用于 MPEG 传输流视频。保留 macOS 原视频类型兼容，不为 TypeScript 强占该后缀；本轮文本样本仅显示文件元数据，未显示正文。 | coverage-typescript.ts | Expected file was inspected but its content marker was not visible; detailed operator note is retained in the local raw record |
| 45 | .tsx | typescript | own-provider-content-pass | — | coverage-typescript.tsx | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 46 | .cts | typescript | own-provider-content-pass | — | coverage-typescript.cts | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 47 | .mts | typescript | fail | .mts 同时用于 MPEG 传输流视频。保留 macOS 原视频类型兼容，不为 TypeScript 强占该后缀；本轮文本样本仅显示文件元数据，未显示正文。 | coverage-typescript.mts | Expected file was inspected but its content marker was not visible; detailed operator note is retained in the local raw record |
| 48 | .py | python | own-provider-content-pass | — | coverage-python.py | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 49 | .pyw | python | own-provider-content-pass | — | coverage-python.pyw | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 50 | .pyi | python | own-provider-content-pass | — | coverage-python.pyi | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 51 | .pyx | python | own-provider-content-pass | — | coverage-python.pyx | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 52 | .pxd | python | own-provider-content-pass | — | coverage-python.pxd | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 53 | .rs | rust | own-provider-content-pass | — | coverage-rust.rs | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 54 | .go | go | own-provider-content-pass | — | coverage-go.go | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 55 | .java | java | own-provider-content-pass | — | coverage-java.java | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 56 | .jav | java | own-provider-content-pass | — | coverage-java.jav | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 57 | .kt | kotlin | own-provider-content-pass | — | coverage-kotlin.kt | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 58 | .kts | kotlin | own-provider-content-pass | — | coverage-kotlin.kts | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 59 | .c | c | own-provider-content-pass | — | coverage-c.c | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 60 | .h | c | own-provider-content-pass | — | coverage-c.h | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 61 | .cc | cpp | own-provider-content-pass | — | coverage-cpp.cc | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 62 | .cpp | cpp | own-provider-content-pass | — | coverage-cpp.cpp | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 63 | .cxx | cpp | own-provider-content-pass | — | coverage-cpp.cxx | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 64 | .c++ | cpp | own-provider-content-pass | — | coverage-cpp.c++ | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 65 | .hh | cpp | own-provider-content-pass | — | coverage-cpp.hh | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 66 | .hpp | cpp | own-provider-content-pass | — | coverage-cpp.hpp | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 67 | .hxx | cpp | own-provider-content-pass | — | coverage-cpp.hxx | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 68 | .h++ | cpp | own-provider-content-pass | — | coverage-cpp.h++ | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 69 | .inl | cpp | own-provider-content-pass | — | coverage-cpp.inl | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 70 | .ipp | cpp | own-provider-content-pass | — | coverage-cpp.ipp | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 71 | .tpp | cpp | own-provider-content-pass | — | coverage-cpp.tpp | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 72 | .m | objective-c | own-provider-content-pass | — | coverage-objective-c.m | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 73 | .mm | objective-c | own-provider-content-pass | — | coverage-objective-c.mm | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 74 | .cs | csharp | own-provider-content-pass | — | coverage-csharp.cs | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 75 | .csx | csharp | own-provider-content-pass | — | coverage-csharp.csx | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 76 | .fs | fsharp | own-provider-content-pass | — | coverage-fsharp.fs | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 77 | .fsx | fsharp | own-provider-content-pass | — | coverage-fsharp.fsx | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 78 | .fsi | fsharp | own-provider-content-pass | — | coverage-fsharp.fsi | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 79 | .vb | visual-basic | own-provider-content-pass | — | coverage-visual-basic.vb | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 80 | .sh | shell | own-provider-content-pass | — | coverage-shell.sh | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 81 | .bash | shell | own-provider-content-pass | — | coverage-shell.bash | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 82 | .zsh | shell | own-provider-content-pass | — | coverage-shell.zsh | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 83 | .ksh | shell | own-provider-content-pass | — | coverage-shell.ksh | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 84 | .csh | shell | own-provider-content-pass | — | coverage-shell.csh | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 85 | .fish | shell | own-provider-content-pass | — | coverage-shell.fish | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 86 | .command | shell | own-provider-content-pass | — | coverage-shell.command | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 87 | .rb | ruby | own-provider-content-pass | — | coverage-ruby.rb | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 88 | .rbw | ruby | own-provider-content-pass | — | coverage-ruby.rbw | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 89 | .rake | ruby | own-provider-content-pass | — | coverage-ruby.rake | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 90 | .gemspec | ruby | own-provider-content-pass | — | coverage-ruby.gemspec | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 91 | .podspec | ruby | own-provider-content-pass | — | coverage-ruby.podspec | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 92 | .php | php | own-provider-content-pass | — | coverage-php.php | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 93 | .php3 | php | own-provider-content-pass | — | coverage-php.php3 | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 94 | .php4 | php | own-provider-content-pass | — | coverage-php.php4 | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 95 | .php5 | php | own-provider-content-pass | — | coverage-php.php5 | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 96 | .php7 | php | own-provider-content-pass | — | coverage-php.php7 | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 97 | .phtml | php | own-provider-content-pass | — | coverage-php.phtml | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 98 | .lua | lua | system-provider-content-pass | — | coverage-lua.lua | Correct title and marker in a native text area; no web provider is present |
| 99 | .luau | lua | own-provider-content-pass | — | coverage-lua.luau | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 100 | .pl | perl | own-provider-content-pass | — | coverage-perl.pl | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 101 | .pm | perl | own-provider-content-pass | — | coverage-perl.pm | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 102 | .r | r | system-provider-content-pass | — | coverage-r.r | Correct title and marker in a native text area; no web provider is present |
| 103 | .rprofile | r | own-provider-content-pass | — | coverage-r.rprofile | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 104 | .jl | julia | own-provider-content-pass | — | coverage-julia.jl | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 105 | .dart | dart | own-provider-content-pass | — | coverage-dart.dart | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 106 | .scala | scala | own-provider-content-pass | — | coverage-scala.scala | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 107 | .sc | scala | own-provider-content-pass | — | coverage-scala.sc | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 108 | .sbt | scala | own-provider-content-pass | — | coverage-scala.sbt | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 109 | .groovy | groovy | own-provider-content-pass | — | coverage-groovy.groovy | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 110 | .gradle | groovy | own-provider-content-pass | — | coverage-groovy.gradle | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 111 | .gvy | groovy | own-provider-content-pass | — | coverage-groovy.gvy | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 112 | .sql | sql | own-provider-content-pass | — | coverage-sql.sql | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 113 | .ddl | sql | own-provider-content-pass | — | coverage-sql.ddl | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 114 | .dml | sql | own-provider-content-pass | — | coverage-sql.dml | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 115 | .css | css | own-provider-content-pass | — | coverage-css.css | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 116 | .scss | scss | own-provider-content-pass | — | coverage-scss.scss | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 117 | .sass | sass | own-provider-content-pass | — | coverage-sass.sass | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 118 | .less | less | own-provider-content-pass | — | coverage-less.less | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 119 | .vue | web-components | own-provider-content-pass | — | coverage-web-components.vue | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 120 | .svelte | web-components | own-provider-content-pass | — | coverage-web-components.svelte | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 121 | .astro | web-components | own-provider-content-pass | — | coverage-web-components.astro | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 122 | .graphql | graphql | own-provider-content-pass | — | coverage-graphql.graphql | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 123 | .gql | graphql | own-provider-content-pass | — | coverage-graphql.gql | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 124 | .graphqls | graphql | own-provider-content-pass | — | coverage-graphql.graphqls | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 125 | .proto | protobuf | own-provider-content-pass | — | coverage-protobuf.proto | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 126 | .cmake | cmake | own-provider-content-pass | — | coverage-cmake.cmake | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 127 | .make | makefile | own-provider-content-pass | — | coverage-makefile.make | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 128 | .mk | makefile | own-provider-content-pass | — | coverage-makefile.mk | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 129 | .mak | makefile | own-provider-content-pass | — | coverage-makefile.mak | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 130 | .dockerfile | dockerfile | own-provider-content-pass | — | coverage-dockerfile.dockerfile | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 131 | .containerfile | dockerfile | own-provider-content-pass | — | coverage-dockerfile.containerfile | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 132 | .diff | diff | own-provider-content-pass | — | coverage-diff.diff | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 133 | .patch | diff | own-provider-content-pass | — | coverage-diff.patch | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 134 | .xml | xml | own-provider-content-pass | — | coverage-xml.xml | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 135 | .xsd | xml | own-provider-content-pass | — | coverage-xml.xsd | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 136 | .xsl | xml | own-provider-content-pass | — | coverage-xml.xsl | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 137 | .xslt | xml | own-provider-content-pass | — | coverage-xml.xslt | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 138 | .xib | xml | own-provider-content-pass | — | coverage-xml.xib | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 139 | .storyboard | xml | own-provider-content-pass | — | coverage-xml.storyboard | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 140 | .wsdl | xml | own-provider-content-pass | — | coverage-xml.wsdl | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 141 | .pom | xml | own-provider-content-pass | — | coverage-xml.pom | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 142 | .resx | xml | own-provider-content-pass | — | coverage-xml.resx | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 143 | .csproj | xml | own-provider-content-pass | — | coverage-xml.csproj | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 144 | .props | xml | own-provider-content-pass | — | coverage-xml.props | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 145 | .targets | xml | own-provider-content-pass | — | coverage-xml.targets | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 146 | .plist | plist | own-provider-content-pass | — | coverage-plist.plist | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 147 | .entitlements | plist | own-provider-content-pass | — | coverage-plist.entitlements | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 148 | .mobileconfig | plist | own-provider-content-pass | — | coverage-plist.mobileconfig | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 149 | .stringsdict | plist | own-provider-content-pass | — | coverage-plist.stringsdict | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 150 | .strings | strings | own-provider-content-pass | — | coverage-strings.strings | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 151 | .hcl | hcl | own-provider-content-pass | — | coverage-hcl.hcl | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 152 | .tf | hcl | own-provider-content-pass | — | coverage-hcl.tf | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 153 | .tfvars | hcl | own-provider-content-pass | — | coverage-hcl.tfvars | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 154 | .nix | nix | own-provider-content-pass | — | coverage-nix.nix | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 155 | .zig | zig | own-provider-content-pass | — | coverage-zig.zig | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 156 | .zon | zig | own-provider-content-pass | — | coverage-zig.zon | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 157 | .ex | elixir | own-provider-content-pass | — | coverage-elixir.ex | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 158 | .exs | elixir | fail | .exs 可用于 Logic 采样器数据。保留 Logic / GarageBand 格式兼容，不接管 com.apple.logic.exs；本轮文本样本仅显示文件元数据，未显示 Elixir 正文。 | coverage-elixir.exs | Expected file was inspected but its content marker was not visible; detailed operator note is retained in the local raw record |
| 159 | .erl | erlang | own-provider-content-pass | — | coverage-erlang.erl | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 160 | .hrl | erlang | own-provider-content-pass | — | coverage-erlang.hrl | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 161 | .hs | haskell | own-provider-content-pass | — | coverage-haskell.hs | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 162 | .lhs | haskell | own-provider-content-pass | — | coverage-haskell.lhs | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 163 | .clj | clojure | own-provider-content-pass | — | coverage-clojure.clj | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 164 | .cljs | clojure | own-provider-content-pass | — | coverage-clojure.cljs | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 165 | .cljc | clojure | own-provider-content-pass | — | coverage-clojure.cljc | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 166 | .edn | clojure | fail | .edn 可被识别为 Adobe DRM 元数据。保留 Adobe 格式兼容，不接管 com.adobe.edn；本轮文本样本仅显示文件元数据，未显示 EDN 正文。 | coverage-clojure.edn | Expected file was inspected but its content marker was not visible; detailed operator note is retained in the local raw record |
| 167 | .el | lisp | own-provider-content-pass | — | coverage-lisp.el | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 168 | .lisp | lisp | own-provider-content-pass | — | coverage-lisp.lisp | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 169 | .lsp | lisp | own-provider-content-pass | — | coverage-lisp.lsp | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 170 | .scm | scheme | own-provider-content-pass | — | coverage-scheme.scm | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 171 | .ss | scheme | own-provider-content-pass | — | coverage-scheme.ss | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 172 | .rkt | scheme | own-provider-content-pass | — | coverage-scheme.rkt | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 173 | .ml | ocaml | own-provider-content-pass | — | coverage-ocaml.ml | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 174 | .mli | ocaml | own-provider-content-pass | — | coverage-ocaml.mli | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 175 | .v | verilog | own-provider-content-pass | — | coverage-verilog.v | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 176 | .sv | verilog | own-provider-content-pass | — | coverage-verilog.sv | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 177 | .vh | verilog | own-provider-content-pass | — | coverage-verilog.vh | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 178 | .svh | verilog | own-provider-content-pass | — | coverage-verilog.svh | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 179 | .vhd | vhdl | own-provider-content-pass | — | coverage-vhdl.vhd | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 180 | .vhdl | vhdl | own-provider-content-pass | — | coverage-vhdl.vhdl | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 181 | .asm | assembly | own-provider-content-pass | — | coverage-assembly.asm | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 182 | .s | assembly | own-provider-content-pass | — | coverage-assembly.s | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 183 | .nasm | assembly | own-provider-content-pass | — | coverage-assembly.nasm | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 184 | .ps1 | powershell | own-provider-content-pass | — | coverage-powershell.ps1 | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 185 | .psm1 | powershell | own-provider-content-pass | — | coverage-powershell.psm1 | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 186 | .psd1 | powershell | own-provider-content-pass | — | coverage-powershell.psd1 | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 187 | .bat | batch | own-provider-content-pass | — | coverage-batch.bat | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 188 | .cmd | batch | own-provider-content-pass | — | coverage-batch.cmd | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 189 | .tex | latex | own-provider-content-pass | — | coverage-latex.tex | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 190 | .sty | latex | own-provider-content-pass | — | coverage-latex.sty | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 191 | .cls | latex | own-provider-content-pass | — | coverage-latex.cls | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 192 | .ltx | latex | own-provider-content-pass | — | coverage-latex.ltx | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 193 | .latex | latex | own-provider-content-pass | — | coverage-latex.latex | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 194 | .bib | bibtex | own-provider-content-pass | — | coverage-bibtex.bib | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 195 | .rst | restructuredtext | own-provider-content-pass | — | coverage-restructuredtext.rst | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 196 | .adoc | asciidoc | own-provider-content-pass | — | coverage-asciidoc.adoc | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 197 | .asciidoc | asciidoc | own-provider-content-pass | — | coverage-asciidoc.asciidoc | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 198 | .wat | wasm-text | own-provider-content-pass | — | coverage-wasm-text.wat | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 199 | .wast | wasm-text | own-provider-content-pass | — | coverage-wasm-text.wast | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 200 | .glsl | shader | own-provider-content-pass | — | coverage-shader.glsl | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 201 | .frag | shader | own-provider-content-pass | — | coverage-shader.frag | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 202 | .vert | shader | own-provider-content-pass | — | coverage-shader.vert | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 203 | .geom | shader | own-provider-content-pass | — | coverage-shader.geom | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 204 | .tesc | shader | own-provider-content-pass | — | coverage-shader.tesc | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 205 | .tese | shader | own-provider-content-pass | — | coverage-shader.tese | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 206 | .comp | shader | own-provider-content-pass | — | coverage-shader.comp | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 207 | .cu | cuda | own-provider-content-pass | — | coverage-cuda.cu | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 208 | .cuh | cuda | own-provider-content-pass | — | coverage-cuda.cuh | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 209 | .ino | arduino | own-provider-content-pass | — | coverage-arduino.ino | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 210 | .d | d | own-provider-content-pass | — | coverage-d.d | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 211 | .di | d | own-provider-content-pass | — | coverage-d.di | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 212 | .nim | nim | own-provider-content-pass | — | coverage-nim.nim | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 213 | .nims | nim | own-provider-content-pass | — | coverage-nim.nims | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 214 | .nimble | nim | own-provider-content-pass | — | coverage-nim.nimble | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 215 | .awk | awk | own-provider-content-pass | — | coverage-awk.awk | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 216 | .tcl | tcl | own-provider-content-pass | — | coverage-tcl.tcl | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 217 | .tk | tcl | own-provider-content-pass | — | coverage-tcl.tk | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 218 | .coffee | coffeescript | own-provider-content-pass | — | coverage-coffeescript.coffee | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 219 | .litcoffee | coffeescript | own-provider-content-pass | — | coverage-coffeescript.litcoffee | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 220 | .handlebars | handlebars | own-provider-content-pass | — | coverage-handlebars.handlebars | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 221 | .hbs | handlebars | own-provider-content-pass | — | coverage-handlebars.hbs | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 222 | .mustache | handlebars | own-provider-content-pass | — | coverage-handlebars.mustache | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 223 | .haml | haml | own-provider-content-pass | — | coverage-haml.haml | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 224 | .erb | erb | own-provider-content-pass | — | coverage-erb.erb | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 225 | .vim | vim | own-provider-content-pass | — | coverage-vim.vim | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 226 | .http | http | own-provider-content-pass | — | coverage-http.http | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |
| 227 | .rest | http | own-provider-content-pass | — | coverage-http.rest | Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed |

## 边界

- Each fixture is a small representative text sample, not every possible file bearing that suffix.
- Native system text classification uses the recorded native AX surface and excludes web providers; it is not a renderer bundle identity attestation.
- Missing observations, missing raw AX, mismatched paths/hashes/titles and unconfirmed providers are never counted as passes.
- A report-time app snapshot does not prove the build used for earlier observations; per-batch runMetadata records that provenance.
- No system reboot, cross-version OS run, or Intel hardware execution is implied by this report.
- Full raw AX remains in ignored observation files. Shareable reports contain only current Quick Look title/content excerpts, evidence digests and local relative references.
- An explicitly supplied versioned policy can accept observed metadata-only compatibility limits for a separate boundary gate; these remain fail and never become content passes.
