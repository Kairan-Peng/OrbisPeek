#!/usr/bin/env python3
"""Exercise the actual Swift loader and WKWebView renderer on core fixtures.

Build quicklook-probe first, then run this script from any directory. Large
fixtures are produced by the existing make-fixtures.py helper under .build.
This smoke test does not launch Finder or prove Quick Look provider selection.
"""

from __future__ import annotations

import argparse
import base64
import collections
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import http.server
import json
from pathlib import Path
import platform
import subprocess
import sys
import threading
import time


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PROBE = ROOT / ".build/debug/quicklook-probe"
DEFAULT_OUTPUT = ROOT / ".build/validation/core-results.json"


@dataclass(frozen=True)
class RenderCase:
    identifier: str
    path: str
    mode: str
    contains: tuple[str, ...] = ()
    valid_json: bool | None = None
    records: int | None = None
    invalid_lines: int | None = None
    truncated: bool = False


CASES = (
    RenderCase("html-default", "samples/fixtures/html/preview.html", "html", ("Static HTML preview", "Root inheritance marker", "Alpha needle beta 你好", "9007199254740993123456789")),
    RenderCase("htm-default", "samples/fixtures/html/preview.htm", "html", ("Static HTML preview", "Root inheritance marker", "Alpha needle beta 你好")),
    RenderCase("xhtml-default", "samples/fixtures/html/preview.xhtml", "html", ("XHTML static preview", "Alpha needle 你好", "Readable cell")),
    RenderCase("html-default-resource-boundaries", "samples/fixtures/html/blocked-resources.html", "html", ("Blocked HTML resources", "Readable sibling", "After blocked resources")),
    RenderCase("markdown", "samples/fixtures/markdown/basic.md", "markdown", ("Quicklook · 文档预览", "GitHub 风格内容", "JSONL", "TOML")),
    RenderCase("markdown-resource-boundaries", "samples/fixtures/markdown/resources.md", "markdown", ("图片与脚本边界", "<script>", "原始 HTML")),
    RenderCase("lossless-json", "samples/fixtures/data/large-integer-duplicate-keys.json", "json", ("9007199254740993123456789", '"first"', '"last"', "中文"), valid_json=True),
    RenderCase("invalid-json-fallback", "samples/fixtures/data/invalid.json", "json", ('"unfinished"', "中文"), valid_json=False),
    RenderCase("jsonl", "samples/fixtures/data/valid.jsonl", "jsonl", ("第一行", "第二行"), records=3, invalid_lines=0),
    RenderCase("jsonl-bad-middle-row", "samples/fixtures/data/bad-middle-row.jsonl", "jsonl", ("有效行", "坏行之后仍能阅读"), records=3, invalid_lines=1),
    RenderCase("jsonl-script-string", "samples/fixtures/data/script-string.ndjson", "jsonl", ("</script><script>", "quicklookFixtureScriptExecuted"), records=1, invalid_lines=0),
    RenderCase("yaml", "samples/fixtures/config/settings.yaml", "code", ("# 保留注释", "轻量预览", "&defaults")),
    RenderCase("toml", "samples/fixtures/config/settings.toml", "code", ("# TOML 配置", "轻量预览", "[server]")),
    RenderCase("properties", "samples/fixtures/config/application.properties", "code", ("# Preserve comments and escapes", r"\u4F60\u597D", "continued=first")),
    RenderCase("ini", "samples/fixtures/config/settings.ini", "code", ("; INI 注释", "[application]", "轻量预览")),
    RenderCase("source-code", "samples/fixtures/code/hello.swift", "code", ("import Foundation", "你好，Quicklook")),
    RenderCase("utf16-bom", "samples/fixtures/encoding/utf16-le-bom.log", "code", ("应用名称=轻量文档预览", "说明=这是用于检查中文配置文件编码")),
    RenderCase("utf16-no-bom", "samples/fixtures/encoding/utf16-be-no-bom.log", "code", ("server.name = 中文服务器", "port = 8080")),
    RenderCase("gb18030-four-byte", "samples/fixtures/encoding/gb18030-four-byte.log", "code", ("应用名称=轻量文档预览", "扩展汉字=𠀀；表情=🧭")),
    RenderCase("big5", "samples/fixtures/encoding/big5.log", "code", ("應用名稱=文件預覽", "支援日誌和程式碼")),
    RenderCase("shift-jis", "samples/fixtures/encoding/shift-jis.log", "code", ("アプリケーション名=書類プレビュー", "文字コードを確認")),
    RenderCase("large-log-prefix", ".build/fixtures/repeated-100MiB.log", "code", ("中文日志", "bounded-preview"), truncated=True),
    RenderCase("large-jsonl-prefix", ".build/fixtures/sparse-prefix-1GiB.jsonl", "jsonl", ("中文日志", "validPrefix"), invalid_lines=0, truncated=True),
)


def relative(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run_json(command: list[str], *, timeout: float) -> tuple[dict | list, dict]:
    started = time.monotonic()
    completed = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    execution = {
        "command": [relative(Path(value)) if value.startswith(str(ROOT)) else value for value in command],
        "exitCode": completed.returncode,
        "wallMilliseconds": round((time.monotonic() - started) * 1000, 3),
        "stderr": completed.stderr[-4000:],
    }
    try:
        output = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError(f"Probe did not return JSON ({completed.returncode}): {completed.stdout[-1000:]} {completed.stderr[-1000:]}") from error
    if completed.returncode:
        raise RuntimeError(f"Probe failed ({completed.returncode}): {output}")
    return output, execution


def render_checks(case: RenderCase, result: dict) -> list[dict]:
    checks: list[dict] = []

    def check(name: str, passed: bool, evidence=None) -> None:
        item = {"name": name, "passed": bool(passed)}
        if evidence is not None:
            item["evidence"] = evidence
        checks.append(item)

    renderer = result.get("renderer", {})
    web = result.get("webView", {})
    text = web.get("text", "")
    check("expected rendering mode", renderer.get("mode") == case.mode, renderer.get("mode"))
    check("rendered document is present", bool(web.get("title")) and "error" not in result, web.get("title"))
    check("only the bundled script is in the DOM", web.get("scripts") == 1, web.get("scripts"))
    check("expected truncation state", renderer.get("truncated") is case.truncated, renderer.get("truncated"))
    for value in case.contains:
        check(f"visible source/content retained: {value}", value in text)
    if case.valid_json is not None:
        check("JSON validity is reported", renderer.get("validJSON") is case.valid_json, renderer.get("validJSON"))
    if case.records is not None:
        check("all nonblank JSONL records remain visible", renderer.get("records") == case.records, renderer.get("records"))
    if case.invalid_lines is not None:
        check("malformed JSONL rows are counted independently", renderer.get("invalidLines") == case.invalid_lines, renderer.get("invalidLines"))
    if case.identifier == "lossless-json":
        check("both duplicate key occurrences survive formatting", text.count('"duplicate"') == 2, text.count('"duplicate"'))
    if case.identifier == "invalid-json-fallback":
        check("parse failure has a readable fallback notice", bool(renderer.get("notices")), renderer.get("notices"))
    if case.identifier in {"markdown-resource-boundaries", "jsonl-script-string"}:
        check("fixture script did not replace the document title", web.get("title") == f"{Path(case.path).name} · OrbisPeek", web.get("title"))
    if case.identifier == "markdown":
        images = web.get("images", [])
        check("local Markdown raster image loaded in host renderer", len(images) == 1 and images[0].get("loaded") is True, images)
    if case.identifier == "markdown-resource-boundaries":
        resources = result.get("resources", [])
        loaded_paths = {entry.get("path", "").lstrip("/") for entry in resources if entry.get("status") == "loaded"}
        blocked_paths = {entry.get("path", "").lstrip("/") for entry in resources if entry.get("status") == "blocked"}
        images = web.get("images", [])
        check("both allowed raster images loaded, including escaped space", {"assets/local-swatch.png", "assets/local swatch.png"}.issubset(loaded_paths), sorted(loaded_paths))
        check("symlink escape was blocked by native resource policy", "assets/outside-link.png" in blocked_paths, sorted(blocked_paths))
        check("SVG was blocked by native raster-only resource policy", "assets/unsafe.svg" in blocked_paths, sorted(blocked_paths))
        check("remote/parent image references blocked before loading", renderer.get("blockedImages", 0) >= 2, renderer.get("blockedImages"))
        check("no external or absolute-file image element was loaded", all(image.get("src", "").startswith("quicklook-resource://local/") for image in images), images)
        check("no forbidden source appears in native loaded resources", not any("outside" in path or path.endswith(".svg") or "://" in path for path in loaded_paths), sorted(loaded_paths))
    if case.mode == "html":
        check("default classifier selected the controlled HTML child body", web.get("bodyKind") == "html" and str(web.get("activeDocumentURL", "")).startswith("quicklook-app://bundle/document/") and str(web.get("activeDocumentURL", "")).endswith("/content.html"), {key: web.get(key) for key in ("bodyKind", "activeDocumentURL")})
        check("untrusted HTML scripts are absent and did not run", web.get("childScripts") == 0 and web.get("untrustedParentScriptRan") is False and web.get("untrustedChildScriptRan") is False, {key: web.get(key) for key in ("childScripts", "untrustedParentScriptRan", "untrustedChildScriptRan")})
        images = web.get("images", [])
        if case.identifier == "html-default-resource-boundaries":
            check("blocked HTML resources produced no image loads", not images and not any(entry.get("status") == "loaded" for entry in result.get("resources", [])), images)
        else:
            check("default HTML body loaded the permitted local raster", any(image.get("loaded") is True and str(image.get("src", "")).startswith("quicklook-resource://local/") for image in images), images)
    if case.truncated:
        check("a bounded prefix is readable and clipping is explained", renderer.get("visibleLineCount", 0) > 0 and bool(renderer.get("notices")), {"visibleLineCount": renderer.get("visibleLineCount"), "notices": renderer.get("notices")})
    return checks


@contextmanager
def loopback_counter():
    """A real WebKit image must decode before a strict-case zero is meaningful."""
    counts = collections.Counter()
    lock = threading.Lock()
    pixel = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")

    class Sentinel(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            with lock:
                counts[self.path] += 1
            is_image = self.path.split("?", 1)[0] == "/image" or self.path.split("?", 1)[0].endswith(".png")
            self.send_response(200)
            self.send_header("Content-Type", "image/png" if is_image else "text/plain")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(pixel if is_image else b"synthetic sentinel")

        do_POST = do_GET

        def log_message(self, *_args):
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Sentinel)
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    try:
        yield f"http://127.0.0.1:{server.server_port}", counts, lock
    finally:
        server.shutdown()
        server.server_close()
        worker.join(timeout=2)


def preview_interactions(probe: Path, directory: Path, timeout: float) -> dict:
    directory.mkdir(parents=True, exist_ok=True)
    checks = []

    def check(name: str, passed: bool, evidence=None):
        checks.append({"name": name, "passed": bool(passed), "evidence": evidence})

    with loopback_counter() as (origin, counts, lock):
        positive, positive_execution = run_json([str(probe), "network-positive", origin, "--output", str(directory / "network-positive.json")], timeout=timeout)
        with lock:
            positive_counts = dict(counts)
            counts.clear()
        image = positive.get("webKitPositive", {})
        check("actual WKWebView loopback image requested and decoded", positive_counts.get("/image", 0) > 0 and image.get("naturalWidth") == 1 and image.get("actualWebKitImage") is True, {"requests": positive_counts, "webKit": image})
        parsed, parse_execution = run_json([str(probe), "network-parse", origin, "--renderer-script", str(ROOT / "Sources/QuicklookUI/Resources/renderer.js"), "--output", str(directory / "html-parse.json")], timeout=timeout)
        with lock:
            parse_counts = dict(counts)
            counts.clear()
        positive_parse = parsed.get("activeOwnedDisconnectedPositive", {})
        check("disconnected active-owned image requests and decodes before append", positive_parse.get("naturalWidth") == 1 and positive_parse.get("connected") is False and sum(value for path, value in parse_counts.items() if path.startswith("/parse-positive.png?")) == 1, {"requests": parse_counts, "positive": positive_parse})
        check("custom scheme disconnected positive requests and decodes", parsed.get("positiveCustomResourceRequests") == 1 and parsed.get("activeOwnedCustomPositive", {}).get("naturalWidth") == 1, parsed.get("activeOwnedCustomPositive"))
        check("actual production sanitizer parse rebuild serialize makes zero image requests with permissive image CSP", parsed.get("actualProductionSanitizer") is True and parsed.get("policyAllowsLoopbackImages") is True and parsed.get("policyAllowsCustomImages") is True and parsed.get("customResourceRequests") == 0 and all(path.startswith("/parse-positive.png?") for path in parse_counts), {"requests": parse_counts, "customRequests": parsed.get("customResourceRequests"), "scope": parsed.get("claimScope")})
        check("full document parser and reconstruction remain inactive with root attributes and script positive control", parsed.get("parserDocumentHasNoView") is True and parsed.get("reconstructionDocumentHasNoView") is True and parsed.get("rootAttributeSerialized") is True and parsed.get("activeScriptControlRan") is True and parsed.get("inactiveParseScriptRan") is False, {key: parsed.get(key) for key in ("parserDocumentHasNoView", "reconstructionDocumentHasNoView", "rootAttributeSerialized", "activeScriptControlRan", "inactiveParseScriptRan")})
        strict, strict_execution = run_json([str(probe), "render", str(ROOT / "samples/fixtures/markdown/basic.md"), "--checks", "html-container", "--loopback-origin", origin, "--output", str(directory / "html-container.json")], timeout=timeout)
        with lock:
            strict_counts = dict(counts)
        html = strict.get("htmlContainer", {})
        check("strict production child made zero automatic loopback requests", sum(strict_counts.values()) == 0, strict_counts)
        html_results = []
        for filename in ("preview.html", "preview.htm", "preview.xhtml", "blocked-resources.html"):
            with lock:
                counts.clear()
            rendered, execution = run_json([str(probe), "render", str(ROOT / "samples/fixtures/html" / filename), "--checks", "html-static", "--loopback-origin", origin, "--output", str(directory / f"html-{filename}.json")], timeout=timeout)
            with lock:
                html_counts = dict(counts)
            observed = rendered.get("htmlStatic", {})
            report = observed.get("report", {})
            prefix = f"HTML {filename}: "
            check(prefix + "production sanitizer and async container default to rendered HTML", observed.get("forcedMode") is True and report.get("mode") == "html" and report.get("sourceMode") is False and observed.get("bodyKind") == "html" and observed.get("sandbox") == "allow-same-origin", {"forcedMode": observed.get("forcedMode"), "registryMode": observed.get("registryMode"), "report": report})
            canvas = observed.get("canvasPolicy", {})
            hosts = canvas.get("hosts", [])
            canvas_names = {"unstyled", "authored-root", "authored-body", "authored-dark-inline", "authored-dark-stylesheet", "authored-dark-root-selector", "authored-dark-universal", "authored-dark-layer"}
            check(prefix + "canvas policy covers actual dark and light hosts and restores appearance", len(hosts) == 2 and {entry.get("host") for entry in hosts} == {"dark", "light"} and canvas.get("originalAppearanceRestored") is True, {"hosts": [entry.get("host") for entry in hosts], "restored": canvas.get("originalAppearanceRestored")})
            presentations = []
            for host in hosts:
                dark = host.get("host") == "dark"
                page = "rgb(30, 32, 36)" if dark else "rgb(255, 255, 255)"
                cases = host.get("cases", [])
                by_name = {entry.get("name"): entry for entry in cases}
                label = prefix + str(host.get("host")) + " host canvas: "
                check(label + "native appearance reached actual main-frame media and system palette", host.get("mainDark") is dark and host.get("parentBackground") == page and len(cases) == len(canvas_names) and set(by_name) == canvas_names, host)
                plain = by_name.get("unstyled", {})
                check(label + "default child paints opaque light Canvas with CanvasText", plain.get("root", {}).get("scheme") == "light" and plain.get("root", {}).get("background") == plain.get("lightCanvas", {}).get("background") == "rgb(255, 255, 255)" and plain.get("root", {}).get("color") == plain.get("lightCanvas", {}).get("color") == plain.get("body", {}).get("color") == "rgb(0, 0, 0)", plain)
                authored_root, authored_body = by_name.get("authored-root", {}), by_name.get("authored-body", {})
                check(label + "authored root and body colors and background remain unchanged", authored_root.get("root", {}).get("color") == authored_root.get("body", {}).get("color") == "rgb(18, 52, 86)" and authored_root.get("root", {}).get("background") == "rgb(255, 255, 255)" and authored_body.get("root", {}).get("color") == "rgb(18, 52, 86)" and authored_body.get("body", {}).get("color") == "rgb(71, 82, 93)" and authored_body.get("body", {}).get("background") == "rgb(240, 241, 242)" and authored_body.get("body", {}).get("inline") == "color:rgb(71,82,93);background:rgb(240,241,242)", {"root": authored_root, "body": authored_body})
                explicit = [by_name.get(name, {}) for name in ("authored-dark-inline", "authored-dark-stylesheet", "authored-dark-root-selector", "authored-dark-universal")]
                check(label + "authored inline html root and universal dark schemes override zero-specificity defaults", all(entry.get("root", {}).get("scheme") == "dark" and entry.get("root", {}).get("background") == entry.get("darkCanvas", {}).get("background") != entry.get("lightCanvas", {}).get("background") and entry.get("root", {}).get("color") == entry.get("darkCanvas", {}).get("color") == entry.get("body", {}).get("color") for entry in explicit) and explicit[0].get("root", {}).get("inline") == "color-scheme:dark", explicit)
                layered = by_name.get("authored-dark-layer", {})
                check(label + "authored layer overrides initial anonymous canvas layer", layered.get("root", {}).get("scheme") == "dark" and layered.get("root", {}).get("background") == "rgb(8, 9, 10)" and layered.get("root", {}).get("color") == layered.get("body", {}).get("color") == "rgb(230, 231, 232)", layered)
                source = host.get("source", {})
                check(label + "toolbar and source retain host system appearance", all(entry.get("mainDark") is dark and entry.get("parentBackground") == entry.get("toolbarBackground") == page for entry in cases) and source.get("kind") == "source" and source.get("mainDark") is dark and source.get("background") == source.get("toolbarBackground") == page and source.get("codeColor") == source.get("parentColor"), source)
                presentations.append({name: {"root": entry.get("root"), "body": entry.get("body")} for name, entry in by_name.items()})
            check(prefix + "HTML canvas and authored presentation are independent of host light or dark mode", len(presentations) == 2 and presentations[0] == presentations[1], presentations)
            whitespace = observed.get("whitespaceCopy", [])
            expected_whitespace_cases = {"pre-line", "pre-normal", "pre-child-normal", "pre-child-nowrap", "inherited-pre", "inherited-pre-wrap", "inherited-break-spaces"}
            check(prefix + "actual WebKit whitespace copy matrix is complete", len(whitespace) == len(expected_whitespace_cases) and {entry.get("name") for entry in whitespace} == expected_whitespace_cases, [entry.get("name") for entry in whitespace])
            for entry in whitespace:
                line_delta, line_height = entry.get("lineDelta", -1), entry.get("lineHeight", -1)
                visual_lines_match = abs(line_delta - line_height) < 1.5 if entry.get("expectedNewline") else abs(line_delta) < 1.5
                # WebKit Selection retains nonpainted line-edge spaces in
                # pre-line; zero-width ranges establish the visible copy text.
                edges = entry.get("lineEdgeSpaceWidths", [])
                line_edges_match = entry.get("name") != "pre-line" or len(edges) == 2 and all(abs(width) < 0.5 for width in edges)
                rendering_matches = (
                    entry.get("copy") == entry.get("expectedCopy")
                    and (entry.get("name") == "pre-line" or entry.get("copy") == entry.get("nativeSelection"))
                    and entry.get("computedWhiteSpace") == entry.get("expectedWhiteSpace")
                    and entry.get("characterAdvance", 0) > 0
                    and abs(entry.get("spaceAdvances", -1) - entry.get("expectedSpaceAdvances", -100)) < 0.15
                    and abs(entry.get("nextLineOffsetAdvances", -1) - (0 if entry.get("expectedNewline") else 6)) < 0.15
                    and visual_lines_match and line_edges_match
                )
                check(prefix + "computed whitespace copy matches actual glyph spacing and line geometry: " + str(entry.get("name")), rendering_matches, entry)
            boundaries = observed.get("whitespaceBoundaryCopy", [])
            check(prefix + "actual WebKit split-inline pre-line matrix is complete", len(boundaries) == 2 and {entry.get("name") for entry in boundaries} == {"newline-before-inline", "newline-after-inline"}, [entry.get("name") for entry in boundaries])
            for entry in boundaries:
                edges = entry.get("lineEdgeSpaceWidths", [])
                boundary_matches = (
                    entry.get("textNodeCount") == 2 and entry.get("computedModes") == ["pre-line", "pre-line"]
                    and entry.get("copy") == "AA\nCC" and entry.get("partial") == "A\nC"
                    and entry.get("withoutPrecedingNewline") == " CC" and entry.get("withoutFollowingNewline") == "AA "
                    and entry.get("characterAdvance", 0) > 0
                    and abs(entry.get("lineDelta", -1) - 30) < 1.5 and abs(entry.get("nextLineOffsetAdvances", -1)) < 0.15
                    and len(edges) == 2 and all(abs(width) < 0.5 for width in edges)
                )
                check(prefix + "split-inline selected copy matches nonpainted line edges and selected boundaries: " + str(entry.get("name")), boundary_matches, entry)
            hidden_root = observed.get("rootAndDetails", {}).get("hiddenRoot", [])
            check(prefix + "root rendering ancestors exclude body search and copy", len(hidden_root) == 4 and {entry.get("rule") for entry in hidden_root} == {"hidden", "display:none", "opacity:0", "content-visibility:hidden"} and all(entry.get("copy") is None and entry.get("matches") == 0 for entry in hidden_root), hidden_root)
            check(prefix + "scripts event attributes and automatic document loaders are absent", observed.get("childScripts") == 0 and observed.get("parentScripts") == 1 and observed.get("parentScriptRan") is False and observed.get("childScriptRan") is False and observed.get("forbiddenNodes") == 0 and observed.get("eventAttributes") == [], {key: observed.get(key) for key in ("childScripts", "parentScripts", "parentScriptRan", "childScriptRan", "forbiddenNodes", "eventAttributes")})
            check(prefix + "strict child makes zero automatic loopback requests", sum(html_counts.values()) == 0, html_counts)
            modes = observed.get("modes", {})
            source, returned = modes.get("source", {}), modes.get("rendered", {})
            check(prefix + "source switch reuses live prepared child without Find controls", source.get("kind") == "source" and source.get("sourceMode") is True and source.get("hiddenFrame") is True and returned.get("sameFrame") is True and returned.get("kind") == "html" and returned.get("sourceMode") is False and returned.get("wrapDisabled") is True and modes.get("noFindUI") is True, modes)
            commands = observed.get("commands", {})
            check(prefix + "standard nil-target menu Copy uses child selection via supplemental responder", commands.get("bodyMenuEnabled") is True and commands.get("bodyCopyUsesSupplementalTarget") is True and commands.get("bodyCopyMatchesCurrentSelection") is True, {key: commands.get(key) for key in ("bodyMenuEnabled", "bodyCopyUsesSupplementalTarget", "bodyCopyMatchesCurrentSelection")})
            selection = commands.get("querySelectAll", {})
            check(prefix + "probe-only editor Copy SelectAll Paste retain native behavior", commands.get("queryCopyUsesInheritedWebKitTarget") is True and commands.get("immediateQueryCopyUsesNativeEditor") is True and commands.get("queryPasteUsesNativeEditor") is True and selection.get("start") == 0 and selection.get("end") == selection.get("length") == 22, {key: commands.get(key) for key in ("queryCopyUsesInheritedWebKitTarget", "immediateQueryCopyUsesNativeEditor", "queryPasteUsesNativeEditor", "querySelectAll")})
            check(prefix + "native Find action is unavailable and no Find UI exists", commands.get("nativeFindUnavailable") is True and commands.get("noFindUI") is True, commands)
            keys = commands.get("keyEquivalents", {})
            key_all, key_copy = keys.get("bodySelectAll", {}), keys.get("bodyCopy", {})
            key_find, key_caps = keys.get("bodyFind", {}), keys.get("capsLockFind", {})
            check(prefix + "direct key-equivalent Cmd+A routes exactly once to current body", key_all.get("handled") is True and key_all.get("calls") == ["selectAll"] and key_all.get("hasSelection") is True, key_all)
            check(prefix + "direct key-equivalent Cmd+C routes exactly once and copies current selection", key_copy.get("handled") is True and key_copy.get("calls") == ["copy"] and key_copy.get("copiedCurrentSelection") is True, key_copy)
            check(prefix + "direct key-equivalent Cmd+F is consumed without Find", key_find.get("handled") is True and key_find.get("effect", {}).get("calls") == [] and key_find.get("effect", {}).get("open") is False and key_find.get("effect", {}).get("focused") is False, key_find)
            check(prefix + "Caps Lock Cmd+F is consumed without Find", key_caps.get("handled") is True and key_caps.get("effect", {}).get("calls") == [] and key_caps.get("effect", {}).get("open") is False, key_caps)
            unsupported = keys.get("unsupportedModifiers", [])
            check(prefix + "Shift Option Control Function key-equivalents delegate without custom commands", len(unsupported) == 4 and {entry.get("modifier") for entry in unsupported} == {"shift", "option", "control", "function"} and all(entry.get("calls") == [] for entry in unsupported), unsupported)
            key_query = keys.get("query", {})
            standard_selection = key_query.get("standardActionSelection", {})
            check(prefix + "probe-only editor key-equivalents retain native selection and copy", key_query.get("calls") == [] and key_query.get("inheritedCopyTarget") is True and key_query.get("copiedNativeEditor") is True and standard_selection.get("start") == 0 and standard_selection.get("end") == standard_selection.get("length") == 17, key_query)
            composition = keys.get("markedText", {})
            check(prefix + "composition hint prevents direct key-equivalent custom commands", composition.get("compositionHintTested") is True and composition.get("calls") == [], composition)
            check(prefix + "all clipboard items types and bytes were restored exactly in memory", commands.get("clipboardAllItemsAndTypesRestoredExactly") is True, commands.get("clipboardScope"))
            capabilities = observed.get("resourceCapabilities", {})
            check(prefix + "authorized local raster loads while missing and wrong capabilities fail", capabilities.get("authorized", {}).get("loaded") is True and capabilities.get("tokenless", {}).get("loaded") is False and capabilities.get("wrongToken", {}).get("loaded") is False, capabilities)
            check(prefix + "ordinary probe metrics read active child body", rendered.get("webView", {}).get("bodyKind") == "html" and rendered.get("webView", {}).get("childScripts") == 0 and bool(rendered.get("webView", {}).get("text")), rendered.get("webView"))
            if filename in ("preview.html", "preview.htm"):
                check(prefix + "author CSS and class names remain isolated readable content", observed.get("childColor") == "rgb(18, 52, 86)" and observed.get("titleSize") == "31px" and observed.get("parentColor") != observed.get("childColor") and modes.get("authorText") == "Author class names remain readable" and "Author class names remain readable" in commands.get("bodySelection", "") and "本地图片不可读" not in commands.get("bodySelection", ""), {key: observed.get(key) for key in ("childColor", "titleSize", "parentColor")})
                root_details = observed.get("rootAndDetails", {})
                authored_root = root_details.get("root", {})
                visible_descendant = root_details.get("visibleDescendant", {})
                check(prefix + "explicitly visible descendant survives visibility-hidden root", visible_descendant.get("copy") == "Root inheritance marker" and visible_descendant.get("visibleMatches") == 1 and visible_descendant.get("hiddenMatches") == 0, visible_descendant)
                check(prefix + "root attributes CSS selector and inline inheritance survive full parsing", authored_root.get("className") == "fixture-root" and authored_root.get("lang") == "zh" and authored_root.get("dir") == "ltr" and authored_root.get("inheritedColor") == "rgb(18, 52, 86)" and authored_root.get("inheritedFontSize") == "19px" and authored_root.get("selectorFontStyle") == "italic", authored_root)
                closed, opened = root_details.get("closed", {}), root_details.get("open", {})
                check(prefix + "closed details native text selection copy and search omit hidden contents", all("Hidden detail needle" not in closed.get(field, "") and "Hidden second summary" not in closed.get(field, "") and "Visible summary" in closed.get(field, "") for field in ("nativeText", "nativeSelection", "copy")) and closed.get("hiddenMatches") == 0 and closed.get("secondSummaryMatches") == 0 and closed.get("summaryMatches") == 1, closed)
                check(prefix + "open details native text selection copy and search include body", all("Hidden detail needle" in opened.get(field, "") and "Hidden second summary" in opened.get(field, "") for field in ("nativeText", "nativeSelection", "copy")) and opened.get("hiddenMatches") == 1, opened)
                check(prefix + "parent detects failed child images without child listeners", report.get("failedImages") == 1 and observed.get("failedPlaceholders") == 1, report)
            if filename == "blocked-resources.html":
                check(prefix + "bad images blocked before child creation with readable siblings", report.get("blockedImages", 0) >= 5 and "Readable sibling" in observed.get("text", "") and "After blocked resources" in observed.get("text", ""), report)
            if filename == "preview.html":
                lifecycle = observed.get("lifecycle", {})
                check(prefix + "hide revokes bridge and old image capability immediately", lifecycle.get("hidden", {}).get("bridgeRejected") is True and lifecycle.get("hidden", {}).get("oldImageLoaded") is False, lifecycle.get("hidden"))
                check(prefix + "reappear reloads same file with fresh usable capabilities", lifecycle.get("newRequestAfterReappear") is True and lifecycle.get("newTokenAfterReappear") is True and lifecycle.get("resumed", {}).get("kind") == "html" and lifecycle.get("resumed", {}).get("loadedImages") == 1, lifecycle)
                check(prefix + "minimize revokes and deminiaturize reloads fresh usable document", lifecycle.get("minimizeRevokedBridge") is True and lifecycle.get("deminiaturizeResumedWithFreshUsableRequest") is True, lifecycle)
                check(prefix + "new file and explicit close defeat scheduled resume", lifecycle.get("newFileWonScheduledResume") is True and lifecycle.get("closeRejectedBridge") is True and lifecycle.get("closeDidNotAutoResume") is True, lifecycle)
            html_results.append({"filename": filename, "execution": execution, "requests": html_counts, "result": rendered})

    check("default shell used the real request-scoped reply handshake", html.get("shellURL") == "quicklook-app://bundle/index.html" and html.get("handshake", {}).get("ok") is True and html.get("staleRequestRejected") is True and html.get("oversizeRejected") is True, {key: html.get(key) for key in ("shellURL", "handshake", "staleRequestRejected", "oversizeRejected")})
    check("child DOM is same-origin and sandbox permits only same origin", html.get("contentDocument") is True and html.get("shellOrigin") == html.get("childOrigin") == "quicklook-app://bundle" and html.get("sandbox") == "allow-same-origin", {key: html.get(key) for key in ("shellOrigin", "childOrigin", "sandbox")})
    check("real child Selection Range TreeWalker and scrolling work", html.get("selection") == html.get("range") == "Alpha needle beta 你好" and len(html.get("treeWalkerMatches", [])) == 2 and html.get("scrollY", 0) > 0, {key: html.get(key) for key in ("selection", "range", "treeWalkerMatches", "scrollY")})
    check("child inline CSS works and cannot style parent", html.get("childColor") == "rgb(18, 52, 86)" and html.get("childInlinePadding") == "13px" and html.get("childHeadingSize") == "31px" and html.get("parentColorBefore") == html.get("parentColorAfter"), {key: html.get(key) for key in ("childColor", "childInlinePadding", "childHeadingSize", "parentColorBefore", "parentColorAfter")})
    final = html.get("finalDocument", {})
    check("document script and event attributes did not execute", final.get("childScriptRan") is False and final.get("parentUntrustedScriptRan") is False and final.get("parentUntrustedEventRan") is False, final)
    check("child frame cannot invoke the preparation bridge", html.get("childBridge", {}).get("ok") is False, html.get("childBridge"))
    resources = html.get("resourceEvidence", [])
    check("stale image capability was rejected by native resource handler", final.get("staleImage", {}).get("naturalWidth") == 0 and any(entry.get("status") == "blocked" and entry.get("path", "").endswith("/missing.png") for entry in resources), resources)
    stale = html.get("staleDocumentNavigation", {})
    check("superseded child URL cannot navigate to stale content", stale.get("staleContentVisible") is False and stale.get("actualURL") != stale.get("attemptedURL"), stale)
    for key in ("pageChildCallbacks", "defaultClientChildCallbacks"):
        observed = html.get(key, {})
        check(f"observed constraint: {key} click/keydown/copy callbacks suppressed", observed.get("counts") == {"click": 0, "keydown": 0, "copy": 0} and observed.get("prevented") == {"click": False, "keydown": False, "copy": False}, observed)
    check("main-frame synthetic event positive control ran", html.get("mainEventPositive") == {"count": 1, "prevented": True}, html.get("mainEventPositive"))
    check("direct child page execution is unavailable", html.get("directChildPageExecutionError", {}).get("domain") == "WKErrorDomain" and html.get("directChildPageExecutionError", {}).get("code") == 4, html.get("directChildPageExecutionError"))
    commands = html.get("nativeMainCommands", {})
    check("explicit native main-frame command reads child selection", commands.get("readSelection", {}).get("text") == "Alpha needle beta 你好", commands.get("readSelection"))
    selected = commands.get("selectAll", {})
    check("explicit native select-all includes child body only", "Child HTML marker" in selected.get("text", "") and "Omega needle bottom" in selected.get("text", "") and selected.get("includesParent") is False, selected)
    marked = commands.get("markAndScroll", {})
    check("probe-only DOM mark and scroll works in child", marked.get("marks") == 1 and marked.get("text") == "Omega needle bottom" and marked.get("scrollY", 0) > 100, marked)
    check("synthetic parent editor can receive native focus", commands.get("focusParentEditor", {}).get("activeElement") == "probe-editor" and commands.get("focusParentEditor", {}).get("value") == "needle", commands.get("focusParentEditor"))
    check("whole-window dismissal revokes preparation", html.get("afterWindowClose", {}).get("ok") is False, html.get("afterWindowClose"))
    return {"passed": all(item["passed"] for item in checks), "checks": checks, "positiveExecution": positive_execution, "strictExecution": strict_execution, "positiveRequests": positive_counts, "strictRequests": strict_counts, "probeResult": strict, "parseExecution": parse_execution, "parseRequests": parse_counts, "parseResult": parsed, "htmlResults": html_results}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--probe", type=Path, default=DEFAULT_PROBE, help="Already-built quicklook-probe executable")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT, help="Consolidated JSON report")
    parser.add_argument("--timeout", type=float, default=30, help="Per-render timeout in seconds")
    parser.add_argument("--include-preview-interactions", action="store_true", help="Also run real WebKit HTML container and loopback network controls")
    args = parser.parse_args()
    probe = args.probe.resolve()
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    raw_directory = output.parent / "core-render"
    raw_directory.mkdir(parents=True, exist_ok=True)
    failures: list[dict] = []
    report = {
        "schemaVersion": 1,
        "startedAt": datetime.now(timezone.utc).isoformat(),
        "operatingSystem": platform.platform(),
        "scope": "Swift bounded loader plus actual WKWebView host rendering; Finder provider execution and sandbox-extension image permissions are separate manual gates.",
        "limitations": [
            "Visible text assertions use the probe's first 2,000 characters, not the entire document DOM.",
            "Script checks cover the supplied literal-script fixtures through title, DOM script count and visible escaped text; they are not a general security audit.",
            "The 1 GiB sparse fixture contains a valid >1 MiB JSONL prefix followed by zero-filled space; this tests bounded prefix loading, not a fully valid 1 GiB JSONL document.",
            "Legacy encoding checks verify the displayed fixture text; very short ambiguous legacy encodings remain heuristic.",
            "Synthetic checks may exercise private text matching and probe-only editors; the product provides no Find controls or Find shortcut.",
        ],
        "inspect": {},
        "renders": [],
    }
    try:
        if not probe.is_file():
            raise RuntimeError(f"Probe executable is missing: {probe}; run swift build --product quicklook-probe first.")
        swift_sources = list((ROOT / "Sources").rglob("*.swift"))
        report["probe"] = {
            "path": relative(probe),
            "sha256": sha256(probe),
            "olderThanSwiftSource": any(path.stat().st_mtime > probe.stat().st_mtime for path in swift_sources),
        }
        inspect_report = output.parent / "core-inspect.json"
        command = [sys.executable, str(ROOT / "scripts/make-fixtures.py"), "--large", "--inspect", "--probe", str(probe), "--report", str(inspect_report)]
        started = time.monotonic()
        inspected = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=max(args.timeout, 90))
        inspection = json.loads(inspect_report.read_text()) if inspect_report.exists() else {}
        report["inspect"] = {
            "exitCode": inspected.returncode,
            "wallMilliseconds": round((time.monotonic() - started) * 1000, 3),
            "stdout": inspected.stdout[-4000:],
            "stderr": inspected.stderr[-4000:],
            "report": relative(inspect_report),
            "results": inspection.get("results", []),
            "failures": inspection.get("failures", []),
        }
        if inspected.returncode or not inspection.get("results"):
            failures.append({"stage": "inspect", "message": "Fixture generation or loader structural validation failed", "details": inspection.get("failures", [])})
        print(f"Inspect: {len(inspection.get('results', []))} fixtures; {len(inspection.get('failures', []))} structural failures", flush=True)

        for case in CASES:
            result_file = raw_directory / f"{case.identifier}.json"
            try:
                result, execution = run_json([str(probe), "render", str(ROOT / case.path), "--output", str(result_file)], timeout=args.timeout)
                if not isinstance(result, dict):
                    raise RuntimeError("Render result must be a JSON object")
                checks = render_checks(case, result)
                failed = [check for check in checks if not check["passed"]]
                report["renders"].append({"case": case.identifier, "path": case.path, "passed": not failed, "checks": checks, "execution": execution, "rawReport": relative(result_file), "probeResult": result})
                for check in failed:
                    failures.append({"stage": "render", "case": case.identifier, "check": check["name"], "evidence": check.get("evidence")})
                print(f"Render {case.identifier}: {'PASS' if not failed else 'FAIL'} ({len(checks)} checks)", flush=True)
            except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
                failures.append({"stage": "render", "case": case.identifier, "message": str(error)})
                report["renders"].append({"case": case.identifier, "path": case.path, "passed": False, "error": str(error)})
                print(f"Render {case.identifier}: FAIL ({error})", flush=True)
        if args.include_preview_interactions:
            interactions = preview_interactions(probe, output.parent / "preview-interactions", args.timeout)
            report["previewInteractions"] = interactions
            for check in interactions["checks"]:
                if not check["passed"]:
                    failures.append({"stage": "preview-interactions", "check": check["name"], "evidence": check.get("evidence")})
            print(f"Preview interactions: {'PASS' if interactions['passed'] else 'FAIL'} ({len(interactions['checks'])} checks)", flush=True)
    except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
        failures.append({"stage": "setup", "message": str(error)})
    report["completedAt"] = datetime.now(timezone.utc).isoformat()
    report["failures"] = failures
    report["summary"] = {
        "passed": not failures,
        "inspectedFiles": len(report["inspect"].get("results", [])),
        "renderedCases": len(report["renders"]),
        "renderChecks": sum(len(case.get("checks", [])) for case in report["renders"]),
        "failedChecks": len(failures),
    }
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(f"Core validation {'passed' if not failures else 'FAILED'}: {output}")
    for failure in failures:
        print(json.dumps(failure, ensure_ascii=False), file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
