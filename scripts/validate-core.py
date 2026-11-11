#!/usr/bin/env python3
"""Exercise the actual Swift loader and WKWebView renderer on core fixtures.

Build quicklook-probe first, then run this script from any directory. Large
fixtures are produced by the existing make-fixtures.py helper under .build.
This smoke test does not launch Finder or prove Quick Look provider selection.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import sys
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
        check("fixture script did not replace the document title", web.get("title") == f"{Path(case.path).name} · Quicklook", web.get("title"))
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
    if case.truncated:
        check("a bounded prefix is readable and clipping is explained", renderer.get("visibleLineCount", 0) > 0 and bool(renderer.get("notices")), {"visibleLineCount": renderer.get("visibleLineCount"), "notices": renderer.get("notices")})
    return checks


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--probe", type=Path, default=DEFAULT_PROBE, help="Already-built quicklook-probe executable")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT, help="Consolidated JSON report")
    parser.add_argument("--timeout", type=float, default=30, help="Per-render timeout in seconds")
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
