#!/usr/bin/env python3
"""Reproducible preview fixtures, optional large inputs, and batch probe checks.

Only Python's standard library is required. Existing files with different contents
are never overwritten. Generated large inputs stay in the ignored .build directory.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import zlib


ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "samples" / "fixtures"
LARGE = ROOT / ".build" / "fixtures"


def png() -> bytes:
    width, height = 160, 96
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for x in range(width):
            color = (34, 124, 157) if (x // 16 + y // 16) % 2 else (241, 219, 178)
            rows.extend(color)

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(rows), level=9))
        + chunk(b"IEND", b"")
    )


def write_missing(path: Path, data: bytes) -> None:
    if path.is_symlink():
        raise RuntimeError(f"Refusing to replace symlink: {path.relative_to(ROOT)}")
    if path.exists():
        if path.read_bytes() != data:
            raise RuntimeError(f"Existing fixture differs; review it before replacing: {path.relative_to(ROOT)}")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def make_small_fixtures() -> list[dict]:
    entries: list[dict] = []

    def add(path: str, text: str | bytes, *, encoding: str = "utf-8", expectation: str = "preview", mode: str = "code", note: str = "") -> None:
        raw = text if isinstance(text, bytes) else text.encode(encoding)
        write_missing(FIXTURES / path, raw)
        entry = {
            "path": str((FIXTURES / path).relative_to(ROOT)),
            "expectation": expectation,
            "mode": mode,
            "sourceEncoding": encoding,
            "bytes": len(raw),
            "sha256": hashlib.sha256(raw).hexdigest(),
        }
        if isinstance(text, str):
            entry["characters"] = len(text)
        if note:
            entry["note"] = note
        entries.append(entry)

    add("markdown/basic.md", """# Quicklook · 文档预览

不打开编辑器，快速阅读 **Markdown**、数据和配置。🧭

## GitHub 风格内容

- [x] 中文和 emoji
- [x] 本地图片
- [ ] 下一步检查 Finder 的 Space 路由

| 格式 | 预期 |
| --- | --- |
| JSONL | 坏行仍可阅读 |
| TOML | 保留注释 |

> 这是引用。原文与渲染应能切换。

```json
{"name":"轻量预览","id":9007199254740993123456789}
```

![本地棋盘图片](assets/local-swatch.png)

[普通链接](https://example.invalid/document)
""", mode="markdown")
    add("markdown/resources.md", """# 图片与脚本边界

同目录子文件应显示：
![允许的本地图片](assets/local-swatch.png)

带空格路径应可解码：
![空格路径](assets/local%20swatch.png)

以下资源应被阻止，不能因为宿主预览成功就认为沙盒扩展也成功：
![远程资源](https://example.invalid/remote.png)
![父目录资源](../outside.png)
![符号链接越界](assets/outside-link.png)
![绝对文件路径](file:///etc/passwd)
![本地SVG](assets/unsafe.svg)

<script>window.quicklookFixtureScriptExecuted = true; document.title = "UNSAFE_SCRIPT_EXECUTED";</script>
<img src="https://example.invalid/html-image.png" onerror="window.quicklookFixtureScriptExecuted=true">

原始 HTML 应显示为文本或被安全处理，不应执行。
""", mode="markdown", note="Only the first two raster images may load; test in the real extension as well as render probe.")
    add("markdown-local-images.md", """# 沙盒本地图片验证

下方应显示 160 × 96 的蓝色与米色棋盘。如果显示资源受限信息，请记录实际 extension 的权限边界。

![同目录子文件夹中的PNG](markdown/assets/local-swatch.png)

远程图片应被阻止：
![远程资源](https://example.invalid/remote.png)
""", mode="markdown", note="A concise fixture for real Finder extension local-image access; host rendering alone is insufficient.")

    write_missing(FIXTURES / "markdown/assets/local-swatch.png", png())
    write_missing(FIXTURES / "markdown/assets/local swatch.png", png())
    write_missing(FIXTURES / "outside.png", png())
    write_missing(FIXTURES / "markdown/assets/unsafe.svg", b'<svg xmlns="http://www.w3.org/2000/svg"><script>window.quicklookFixtureScriptExecuted=true</script><rect width="80" height="40" fill="red"/></svg>\n')
    symlink = FIXTURES / "markdown/assets/outside-link.png"
    if symlink.is_symlink():
        if os.readlink(symlink) != "../../outside.png":
            raise RuntimeError(f"Existing symlink differs: {symlink}")
    elif symlink.exists():
        raise RuntimeError(f"Refusing to replace existing file with symlink: {symlink}")
    else:
        symlink.symlink_to("../../outside.png")

    add("data/valid.json", '{"name":"轻量预览","enabled":true,"nested":{"list":[1,2,3]},"empty":null}\n', mode="json")
    add("data/large-integer-duplicate-keys.json", '{"large":9007199254740993123456789,"duplicate":"first","duplicate":"last","unicode":"中文"}\n', mode="json", note="Rendering/formatting must retain both duplicate keys and every digit, not JSON.parse/stringify the source.")
    add("data/invalid.json", '{"message":"中文","items":[1,2,],"unfinished":\n', mode="json", note="Loader succeeds; renderer must retain readable raw text and explain parse failure.")
    add("data/valid.jsonl", '{"id":1,"message":"第一行"}\n{"id":2,"message":"第二行"}\n{"id":3,"nested":{"ok":true}}\n', mode="jsonl")
    add("data/bad-middle-row.jsonl", '{"id":1,"message":"有效行"}\n\n{"id":2,"broken":}\n{"id":3,"message":"坏行之后仍能阅读"}\n', mode="jsonl", note="One malformed record must not hide the valid record after it; preserve line numbers including blank lines.")
    add("data/script-string.ndjson", '{"html":"</script><script>window.quicklookFixtureScriptExecuted=true</script>","safe":true}\n', mode="jsonl")
    add("data/comments.jsonc", '// A config with comments\n{"name":"中文", "items":[1,2,],}\n')
    add("data/example.json5", "// JSON5 is code highlighting, not strict JSON\n{name:'中文', count:0x10, trailing:[1,2,],}\n")

    add("config/settings.yaml", "# 保留注释\nname: 轻量预览\nenabled: true\ndefaults: &defaults\n  timeout: 30\nserver:\n  <<: *defaults\n  query: |\n    SELECT id, name FROM files\n    WHERE extension = 'md';\n")
    add("config/settings.yml", "# yml alias\nitems:\n  - name: 中文\n    path: ./文档\n")
    add("config/settings.toml", '# TOML 配置\nname = "轻量预览"\nenabled = true\n[server]\nport = 8080\npaths = ["文档", "代码"]\n')
    add("config/application.properties", "# Preserve comments and escapes\napp.name=轻量预览\ngreeting=\\u4F60\\u597D\nserver.port=8080\ncontinued=first\\\n  second\n")
    add("config/settings.ini", "; INI 注释\n[application]\nname=轻量预览\nenabled=true\n[server]\nport=8080\n")
    add("config/settings.conf", "# Generic .conf is not necessarily TOML\nserver {\n    listen 8080;\n    server_name localhost;\n}\n")
    add("config/settings.cfg", "# .cfg could contain many dialects\n[general]\nname = 中文配置\n")
    add("config/.env", "# 环境变量；预览不得执行\nAPP_NAME=Quicklook\nAPP_GREETING='中文'\nCOMMAND='$(touch /tmp/quicklook-fixture-must-not-execute)'\n")
    add("config/.gitignore", ".build/\nnode_modules/\n*.log\n")
    add("config/.zshrc", "# 配置仅预览，不执行\nexport QUICKLOOK_FIXTURE=1\nalias ql='echo preview'\n")
    add("config/Dockerfile", "FROM alpine:3\nWORKDIR /app\nCOPY . .\nCMD [\"echo\", \"中文\"]\n")
    add("config/Makefile", ".PHONY: preview\npreview:\n\t@echo '中文预览，只显示不执行'\n")
    add("config/README", "无扩展名 README\n这是一份纯文本说明，不应因为没有扩展名而被判为二进制。\n")

    sources = {
        "hello.swift": 'import Foundation\nlet greeting = "你好，Quicklook"\nprint(greeting)\n',
        "hello.py": 'from pathlib import Path\n\ndef preview(path: Path) -> str:\n    """仅预览，不执行。"""\n    return path.name\n',
        "hello.js": 'export const greeting = "中文";\nexport async function preview(value) { return JSON.stringify(value); }\n',
        "hello.ts": 'interface Document { name: string; size: number }\nexport const document: Document = {name: "中文", size: 42};\n',
        "hello.tsx": 'export function Preview() { return <article aria-label="中文">Quicklook</article>; }\n',
        "hello.go": 'package main\nimport "fmt"\nfunc main() { fmt.Println("中文预览") }\n',
        "hello.rs": 'fn main() {\n    let name = "中文预览";\n    println!("{name}");\n}\n',
        "Hello.java": 'public class Hello { public static void main(String[] args) { System.out.println("中文"); } }\n',
        "hello.c": '#include <stdio.h>\nint main(void) { puts("preview"); return 0; }\n',
        "hello.cpp": '#include <iostream>\nint main() { std::cout << "中文预览" << std::endl; }\n',
        "query.sql": "-- 中文注释\nSELECT name, size FROM documents WHERE extension IN ('md', 'jsonl');\n",
        "preview.sh": '#!/bin/sh\n# This fixture must never be executed\nprintf "%s\\n" "中文预览"\n',
        "style.css": '/* 中文注释 */\n.preview { color: #227c9d; max-width: 72ch; }\n',
        "change.diff": '--- a/config.toml\n+++ b/config.toml\n@@ -1 +1 @@\n-name = "before"\n+name = "中文"\n',
    }
    for name, text in sources.items():
        add(f"code/{name}", text)

    add("text/application.log", "2026-11-10T22:00:00+08:00 INFO 开始预览\n2026-11-10T22:00:01+08:00 WARN 单条记录超过显示范围\n2026-11-10T22:00:02+08:00 ERROR 示例错误，仍可阅读\n")
    add("text/empty.log", "")
    add("text/long-line.log", "long_line=" + "中文abcdefghijklmnopqrstuvwxyz" * 1024 + "\n", note="Toggle wrapping; narrow preview must not make controls inaccessible.")
    add("text/system-preview.txt", "TXT 应保留系统 Quick Look 预览。\n", expectation="system", note="Direct inspect can read this; real Finder provider should remain the system provider.")
    add("text/system-preview.html", "<!doctype html><html lang=\"zh\"><meta charset=\"utf-8\"><title>系统 HTML</title><h1>保留系统预览</h1><p>Quicklook 不注册接管 HTML。</p></html>\n", expectation="system")

    cjk = "应用名称=轻量文档预览\n说明=这是用于检查中文配置文件编码的测试内容，支持日志和源代码。\n"
    add("encoding/utf8.log", cjk)
    add("encoding/utf8-bom.log", cjk, encoding="utf-8-sig")
    add("encoding/utf16-le-bom.log", b"\xff\xfe" + cjk.encode("utf-16-le"), encoding="UTF-16 LE BOM")
    add("encoding/utf16-be-bom.log", b"\xfe\xff" + cjk.encode("utf-16-be"), encoding="UTF-16 BE BOM")
    add("encoding/utf16-le-no-bom.log", "server.name = 中文服务器\nenabled = true\nport = 8080\n", encoding="utf-16-le", note="ASCII-heavy BOMless UTF-16 pattern should be inferred before NUL binary detection.")
    add("encoding/utf16-be-no-bom.log", "server.name = 中文服务器\nenabled = true\nport = 8080\n", encoding="utf-16-be")
    add("encoding/gb18030-short.log", "中文日志", encoding="gb18030", expectation="heuristic", note="Very short legacy-encoding inputs are ambiguous; inspect alone cannot prove the displayed text is correct.")
    add("encoding/gb18030-medium.log", cjk * 8, encoding="gb18030")
    add("encoding/gb18030-long.log", cjk * 512, encoding="gb18030")
    add("encoding/gb18030-four-byte.log", (cjk + "扩展汉字=𠀀；表情=🧭\n") * 8, encoding="gb18030")
    add("encoding/gbk.log", cjk * 8, encoding="gbk")
    add("encoding/big5.log", "應用名稱=文件預覽\n說明=這是用來檢查繁體中文設定檔編碼的測試內容，支援日誌和程式碼。\n" * 8, encoding="big5")
    add("encoding/shift-jis.log", "アプリケーション名=書類プレビュー\n説明=これは日本語の設定ファイルとログの文字コードを確認するためのテストです。\n" * 8, encoding="shift_jis")
    add("binary/image-disguised-as-log.log", png(), expectation="reject", encoding="binary", note="PNG signature and binary content must be rejected even with a .log suffix.")
    add("binary/invalid-utf16-bom.log", b"\xff\xfe\x41", expectation="reject", encoding="invalid UTF-16", note="Odd trailing byte must not be silently discarded by Foundation.")

    write_missing(FIXTURES / "README.md", b"""# Generated preview fixtures

Recreate/check these fixtures with `python3 scripts/make-fixtures.py`.
Existing files with different contents are deliberately not overwritten.

`manifest.json` records intended reader behavior, source encoding, and hashes.
Binary inputs are intentional rejection cases. TXT and HTML are system-provider
regression cases. Legacy encoding detection is heuristic; verify displayed text.

The raster checkerboard images are generated locally with Python's standard
library. The Markdown resource fixture includes blocked remote, parent-path,
symlink, file-URL, SVG, and script examples. Do not execute source fixtures.

Large files are opt-in: `python3 scripts/make-fixtures.py --large` creates ignored
inputs under `.build/fixtures`, never source-controlled 100 MiB / 1 GiB files.
""")
    manifest = {"schemaVersion": 1, "fixtures": entries}
    write_missing(FIXTURES / "manifest.json", (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode())
    return entries


def write_repeat_file(path: Path, size: int, record: bytes) -> None:
    if path.exists():
        if path.is_symlink() or path.stat().st_size != size:
            raise RuntimeError(f"Existing large fixture differs: {path}")
        with path.open("rb") as handle:
            if handle.read(len(record)) != record:
                raise RuntimeError(f"Existing large fixture has an unexpected prefix: {path}")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    records, remainder = divmod(size, len(record))
    block_records = 8192
    block = record * block_records
    with path.open("xb") as handle:
        while records >= block_records:
            handle.write(block)
            records -= block_records
        handle.write(record * records)
        if remainder:
            handle.write(b" " * (remainder - 1) + b"\n")


def make_large_fixtures() -> list[dict]:
    log_path = LARGE / "repeated-100MiB.log"
    log_record = "2026-11-10T22:00:00+08:00 INFO 中文日志 record=bounded-preview\n".encode()
    write_repeat_file(log_path, 100 * 1024 * 1024, log_record)

    sparse_path = LARGE / "sparse-prefix-1GiB.jsonl"
    jsonl_record = '{"id":1,"message":"中文日志","validPrefix":true}\n'.encode()
    if sparse_path.exists():
        if sparse_path.is_symlink() or sparse_path.stat().st_size != 1024**3:
            raise RuntimeError(f"Existing sparse fixture differs: {sparse_path}")
        with sparse_path.open("rb") as handle:
            if handle.read(len(jsonl_record)) != jsonl_record:
                raise RuntimeError(f"Existing sparse fixture has an unexpected prefix: {sparse_path}")
    else:
        sparse_path.parent.mkdir(parents=True, exist_ok=True)
        with sparse_path.open("xb") as handle:
            handle.write(jsonl_record * (1024 * 1024 // len(jsonl_record) + 1))
            handle.truncate(1024**3)

    return [
        {"path": str(log_path.relative_to(ROOT)), "expectation": "preview", "mode": "code", "bytes": 100 * 1024 * 1024, "truncated": True},
        {"path": str(sparse_path.relative_to(ROOT)), "expectation": "preview", "mode": "jsonl", "bytes": 1024**3, "truncated": True,
         "note": "Only the first >1 MiB contains valid UTF-8 JSONL. The remaining sparse range is zero-filled; this measures bounded prefix reading, not parsing a valid 1 GiB document."},
    ]


def inspect(entries: list[dict], probe: Path, report: Path) -> int:
    if not probe.is_file():
        raise RuntimeError(f"Probe executable missing: {probe}; build quicklook-probe first.")
    paths = [str(ROOT / entry["path"]) for entry in entries]
    completed = subprocess.run([str(probe), "inspect", *paths], check=True, text=True, capture_output=True)
    results = json.loads(completed.stdout)
    by_path = {str(Path(row["file"]).resolve()): row for row in results}
    failures = []
    for entry in entries:
        result = by_path.get(str((ROOT / entry["path"]).resolve()))
        if result is None:
            failures.append({"path": entry["path"], "reason": "No inspect result"})
            continue
        if entry["expectation"] == "reject":
            if "error" not in result:
                failures.append({"path": entry["path"], "reason": "Binary/malformed encoding was not rejected"})
            continue
        if "error" in result:
            failures.append({"path": entry["path"], "reason": result["error"]})
            continue
        if result["bytesRead"] > 524_288 + 4:
            failures.append({"path": entry["path"], "reason": "Bounded-read budget exceeded"})
        if result["totalBytes"] != entry["bytes"]:
            failures.append({"path": entry["path"], "reason": "File size differs"})
        if result["truncated"] != entry.get("truncated", entry["bytes"] > 524_288):
            failures.append({"path": entry["path"], "reason": "Unexpected truncation flag"})
        if entry["expectation"] not in ("heuristic", "system") and result["mode"] != entry["mode"]:
            failures.append({"path": entry["path"], "reason": f"Expected mode {entry['mode']}, got {result['mode']}"})
        if entry["expectation"] != "heuristic" and not result["truncated"] and "characters" in entry:
            if result["characters"] != entry["characters"]:
                failures.append({"path": entry["path"], "reason": "Decoded character count differs (check source encoding)"})
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps({"results": results, "failures": failures}, ensure_ascii=False, indent=2) + "\n")
    print(f"Inspected {len(entries)} files; {len(failures)} structural failures. Report: {report}")
    for failure in failures:
        print(f"  {failure['path']}: {failure['reason']}", file=sys.stderr)
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--large", action="store_true", help="Also create 100 MiB repeated text and 1 GiB sparse-prefix inputs in .build/fixtures")
    parser.add_argument("--inspect", action="store_true", help="Batch the generated inputs through quicklook-probe inspect and check structural expectations")
    parser.add_argument("--probe", type=Path, default=ROOT / ".build/debug/quicklook-probe", help="Path to the already-built probe executable")
    parser.add_argument("--report", type=Path, default=ROOT / ".build/validation/fixture-inspect.json", help="JSON output for --inspect")
    args = parser.parse_args()
    try:
        entries = make_small_fixtures()
        if args.large:
            entries.extend(make_large_fixtures())
        print(f"Verified {len(entries)} fixtures. Manifest: {FIXTURES / 'manifest.json'}")
        return inspect(entries, args.probe.resolve(), args.report.resolve()) if args.inspect else 0
    except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Fixture generation/check failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
