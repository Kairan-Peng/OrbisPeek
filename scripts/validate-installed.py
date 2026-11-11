#!/usr/bin/env python3
"""Read-only validation of a built or installed Quicklook application.

This validates bundle contents and local registration evidence, not whether
Finder has invoked the extension. It never installs, deletes, enables, repairs,
notarizes, uploads or restarts software.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys


DEFAULT_BUNDLE_ID = "org.quicklook.preview"
DEFAULT_EXTENSION_ID = DEFAULT_BUNDLE_ID + ".extension"
PRESERVED_TYPES = {
    "public.data", "public.content", "public.text", "public.plain-text", "public.source-code",
    "public.html", "public.xhtml", "com.adobe.pdf", "public.comma-separated-values-text",
    "com.microsoft.word.doc", "com.microsoft.excel.xls", "com.microsoft.powerpoint.ppt",
    "org.openxmlformats.wordprocessingml.document", "org.openxmlformats.spreadsheetml.sheet",
    "org.openxmlformats.presentationml.presentation",
}
LICENSE_NAMES = {
    "Quicklook-LICENSE.txt", "FreeLook-LICENSE.txt", "QLStephenSwift-LICENSE.txt",
    "THIRD_PARTY_NOTICES.txt",
}


def parse_registrations(output: str, identifier: str) -> list[dict]:
    """Preserve election evidence without treating a default election as enabled."""
    records = []
    pattern = re.compile(r"^\s*(?P<marker>[+!\-?]?)\s*(?P<id>[^\s(]+)\((?P<version>[^)]*)\)")
    for line in output.splitlines():
        match = pattern.match(line)
        if not match or match["id"] != identifier:
            continue
        fields = line.split("\t")
        path = fields[-1].strip() if len(fields) > 1 else ""
        if not path.startswith("/"):
            fallback = re.search(r"\s(/[^\n]+)$", line)
            path = fallback.group(1).strip() if fallback else ""
        marker = match["marker"]
        records.append({
            "identifier": match["id"], "version": match["version"],
            "electionMarker": marker,
            "election": {"+": "use", "-": "ignore", "": "default"}.get(marker, "unknown"),
            "path": path or None,
        })
    return records


def inside(path: Path, directory: Path) -> bool:
    return path == directory or directory in path.parents


def run_tool(command: list[str], timeout: int = 20) -> dict:
    if not shutil.which(command[0]):
        return {"status": "unknown", "reason": f"Tool unavailable: {command[0]}"}
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"status": "unknown", "reason": str(error)}
    return {
        "status": "completed", "exitCode": result.returncode,
        "stdout": result.stdout, "stderr": result.stderr[-8000:],
    }


def signature_details(bundle: Path) -> tuple[dict, dict]:
    display = run_tool(["codesign", "--display", "--verbose=4", str(bundle)])
    if display["status"] != "completed" or display["exitCode"]:
        return {}, display
    text = display["stdout"] + "\n" + display["stderr"]
    team = re.search(r"^TeamIdentifier=(.+)$", text, re.MULTILINE)
    return {
        "kind": "developer-id" if "Authority=Developer ID Application:" in text
            else "ad-hoc" if "Signature=adhoc" in text else "other",
        "teamIdentifier": team.group(1).strip() if team else None,
        "hardenedRuntime": bool(re.search(r"flags=[^\n]*\bruntime\b", text)),
    }, display


def read_entitlements(bundle: Path) -> tuple[dict | None, dict]:
    result = run_tool(["codesign", "--display", "--entitlements", ":-", str(bundle)])
    if result["status"] != "completed" or result["exitCode"]:
        return None, result
    raw = result["stdout"]
    start = raw.find("<?xml")
    if start < 0:
        start = raw.find("<plist")
    try:
        value = plistlib.loads(raw[start:].encode()) if start >= 0 else {}
        if not isinstance(value, dict):
            return None, {"status": "unknown", "reason": "Entitlements are not a property-list dictionary"}
        return value, result
    except (ValueError, plistlib.InvalidFileException) as error:
        return None, {"status": "unknown", "reason": f"Could not parse entitlements: {error}"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path, help="Exact .app path to inspect, including an absent uninstall target")
    parser.add_argument("--mode", choices=["development", "release", "absent"], default="development")
    parser.add_argument("--bundle-id", default=DEFAULT_BUNDLE_ID)
    parser.add_argument("--extension-id", default=DEFAULT_EXTENSION_ID)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--expect-version")
    parser.add_argument("--expect-build")
    parser.add_argument("--expect-arch", action="append", default=[], help="Repeat for every required architecture")
    parser.add_argument("--require-registered", action="store_true")
    parser.add_argument("--require-enabled", action="store_true", help="Require an explicit pluginkit '+' election at this exact app")
    parser.add_argument("--require-installed", action="store_true", help="Require /Applications or ~/Applications")
    parser.add_argument("--require-no-copies", action="store_true", help="In absent mode, fail if another registered live copy exists")
    args = parser.parse_args()
    app = args.app.expanduser().resolve()
    checks = []
    metadata: dict = {}

    def check(name: str, passed: bool | None, evidence=None, *, required: bool = True):
        status = "unknown" if passed is None else "pass" if passed else "fail" if required else "warning"
        item = {"name": name, "status": status, "required": required}
        if evidence is not None:
            item["evidence"] = evidence
        checks.append(item)

    query = run_tool(["pluginkit", "-m", "-A", "-v", "-i", args.extension_id])
    registrations: list[dict] | None = None
    if query["status"] == "completed" and query["exitCode"] == 0:
        registrations = parse_registrations(query["stdout"], args.extension_id)
        for record in registrations:
            path = Path(record["path"]).resolve() if record["path"] else None
            record["pathExists"] = path.exists() if path else None
            record["insideTargetApp"] = inside(path, app) if path else None
        metadata["registrations"] = registrations
    else:
        metadata["registrationQuery"] = query

    if args.mode == "absent":
        check("target application is absent", not app.exists(), str(app))
        if registrations is None:
            check("no live extension registered inside target", None, metadata["registrationQuery"])
        else:
            live_target = [r for r in registrations if r["insideTargetApp"] and r["pathExists"]]
            others = [r for r in registrations if not r["insideTargetApp"] and r["pathExists"]]
            stale = [r for r in registrations if r["insideTargetApp"] and not r["pathExists"]]
            unlocated = [r for r in registrations if not r["path"]]
            check("no live extension registered inside target", None if unlocated else not live_target,
                  unlocated or live_target)
            check("no other registered live copy", not others, others, required=args.require_no_copies)
            check("no stale target registration", not stale, stale, required=False)
    else:
        check("application bundle exists", app.is_dir() and app.suffix == ".app", str(app))
        host_info = app / "Contents/Info.plist"
        info = None
        try:
            info = plistlib.loads(host_info.read_bytes())
            check("host bundle metadata readable", isinstance(info, dict))
            if not isinstance(info, dict):
                info = None
        except (OSError, ValueError, plistlib.InvalidFileException) as error:
            check("host bundle metadata readable", False, str(error))

        extension = None
        extension_info = None
        if info:
            metadata["bundleIdentifier"] = info.get("CFBundleIdentifier")
            metadata["version"] = info.get("CFBundleShortVersionString")
            metadata["build"] = info.get("CFBundleVersion")
            check("expected host bundle identifier", info.get("CFBundleIdentifier") == args.bundle_id, info.get("CFBundleIdentifier"))
            if args.expect_version:
                check("expected version", info.get("CFBundleShortVersionString") == args.expect_version, metadata["version"])
            if args.expect_build:
                check("expected build", str(info.get("CFBundleVersion")) == args.expect_build, metadata["build"])
            standard = any(inside(app, directory.resolve()) for directory in [Path("/Applications"), Path.home() / "Applications"])
            check("standard installation directory", standard, str(app), required=args.require_installed)
            for candidate in sorted((app / "Contents/PlugIns").glob("*.appex")):
                try:
                    candidate_info = plistlib.loads((candidate / "Contents/Info.plist").read_bytes())
                except (OSError, ValueError, plistlib.InvalidFileException):
                    continue
                if isinstance(candidate_info, dict) and candidate_info.get("CFBundleIdentifier") == args.extension_id:
                    extension, extension_info = candidate, candidate_info
                    break
            check("expected preview extension embedded", extension is not None, str(extension) if extension else args.extension_id)

        for label, bundle, bundle_info in [("host", app, info), ("extension", extension, extension_info)]:
            if not bundle or not bundle_info:
                continue
            name = bundle_info.get("CFBundleExecutable", "")
            valid_name = isinstance(name, str) and name == Path(name).name and name != ""
            binary = bundle / "Contents/MacOS" / (name if valid_name else "<invalid executable>")
            check(f"{label} executable exists", valid_name and binary.is_file(), str(binary))
            architecture = run_tool(["lipo", "-archs", str(binary)]) if valid_name and binary.is_file() else {"status": "unknown", "reason": "Executable missing"}
            if architecture["status"] == "completed" and architecture["exitCode"] == 0:
                archs = architecture["stdout"].strip().split()
                metadata[f"{label}Architectures"] = archs
                check(f"{label} required architectures", set(args.expect_arch).issubset(archs), archs)
            else:
                check(f"{label} required architectures", None, architecture, required=bool(args.expect_arch))

            verified = run_tool(["codesign", "--verify", "--deep", "--strict", str(bundle)])
            check(f"{label} code signature verifies", verified.get("exitCode") == 0 if verified["status"] == "completed" else None,
                  {k: v for k, v in verified.items() if k != "stdout"})
            signature, display = signature_details(bundle)
            metadata[f"{label}Signature"] = signature
            check(f"{label} Developer ID signature", signature.get("kind") == "developer-id" if signature else None,
                  signature, required=args.mode == "release")
            check(f"{label} hardened runtime", signature.get("hardenedRuntime") if signature else None,
                  signature, required=args.mode == "release")
            entitlements, entitlement_result = read_entitlements(bundle)
            metadata[f"{label}Entitlements"] = entitlements
            if entitlements is None:
                check(f"{label} entitlements readable", None, entitlement_result)
            else:
                check(f"{label} sandbox enabled", entitlements.get("com.apple.security.app-sandbox") is True)
                check(f"{label} no debugger entitlement", entitlements.get("com.apple.security.get-task-allow") is not True,
                      required=args.mode == "release")
                temporary = entitlements.get("com.apple.security.temporary-exception.files.absolute-path.read-only", [])
                check(f"{label} no full-disk temporary exception", "/" not in temporary, temporary)
                configured = bundle_info.get("QuicklookAppGroup") or ""
                groups = entitlements.get("com.apple.security.application-groups", [])
                check(f"{label} configured App Group entitlement", not configured or configured in groups,
                      {"configured": configured, "entitled": groups})

            debug = [str(p.relative_to(bundle)) for p in bundle.rglob("*") if p.name.endswith(".debug.dylib") or p.name == "__preview.dylib"]
            check(f"{label} no debug injection libraries", not debug, debug, required=args.mode == "release")

        if info and extension_info:
            check("host and extension version match", all(
                info.get(key) == extension_info.get(key) for key in ["CFBundleShortVersionString", "CFBundleVersion"]
            ), {"host": [info.get("CFBundleShortVersionString"), info.get("CFBundleVersion")],
                "extension": [extension_info.get("CFBundleShortVersionString"), extension_info.get("CFBundleVersion")]})
            check("host and extension App Group match", (info.get("QuicklookAppGroup") or "") == (extension_info.get("QuicklookAppGroup") or ""))
            host_team = metadata.get("hostSignature", {}).get("teamIdentifier")
            extension_team = metadata.get("extensionSignature", {}).get("teamIdentifier")
            check("host and extension signing team match", host_team is not None and host_team == extension_team,
                  {"host": host_team, "extension": extension_team}, required=args.mode == "release")
            declaration = extension_info.get("NSExtension", {})
            check("Quick Look preview extension point", declaration.get("NSExtensionPointIdentifier") == "com.apple.quicklook.preview")
            supported = declaration.get("NSExtensionAttributes", {}).get("QLSupportedContentTypes", [])
            valid_supported = isinstance(supported, list) and bool(supported) and all(isinstance(item, str) for item in supported)
            check("exact preview types declared", valid_supported, len(supported) if isinstance(supported, list) else "Invalid type list")
            if not valid_supported:
                supported = []
            check("system preview types remain unclaimed", not PRESERVED_TYPES.intersection(supported), sorted(PRESERVED_TYPES.intersection(supported)))
            license_files = [p for p in app.rglob("*") if p.is_file() and p.name in LICENSE_NAMES]
            present = {p.name for p in license_files if p.stat().st_size > 0}
            check("runtime license texts bundled", LICENSE_NAMES.issubset(present), sorted(present))
            notices = "\n".join(p.read_text(errors="replace") for p in license_files if p.name == "THIRD_PARTY_NOTICES.txt").lower()
            check("renderer runtime components acknowledged", all(name in notices for name in ["markdown-it", "highlight.js", "jsonc-parser"]))

        exact = [r for r in registrations or [] if r["insideTargetApp"] and r["pathExists"]]
        unlocated = [r for r in registrations or [] if not r["path"]]
        has_target_evidence = bool(exact) if registrations is not None and (exact or not unlocated) else None
        check("extension registered at target application", has_target_evidence,
              exact if registrations is not None else metadata["registrationQuery"], required=args.require_registered or args.require_enabled)
        check("target extension explicitly elected for use", any(r["election"] == "use" for r in exact) if has_target_evidence is not None else None,
              exact if registrations is not None else metadata["registrationQuery"], required=args.require_enabled)
        other = [r for r in registrations or [] if not r["insideTargetApp"] and r["pathExists"]]
        check("no other registered live copy of this extension", not other if registrations is not None and not unlocated else None,
              unlocated or other, required=False)

    check("notarization assessment", None, "No online Gatekeeper or notarization assessment performed by this read-only script.", required=False)
    failures = [c["name"] for c in checks if c["required"] and c["status"] in {"fail", "unknown"}]
    report = {
        "schemaVersion": 1, "checkedAt": datetime.now(timezone.utc).isoformat(),
        "scope": "Read-only bundle and local registration evidence; actual Finder provider execution is a separate gate.",
        "mode": args.mode, "targetApplication": str(app), "metadata": metadata, "checks": checks,
        "summary": {
            "passed": not failures, "requiredFailures": failures,
            "warnings": sum(c["status"] == "warning" for c in checks),
            "unknownChecks": sum(c["status"] == "unknown" for c in checks),
        },
    }
    encoded = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded)
        print(json.dumps({**report["summary"], "report": str(args.output.resolve())}, ensure_ascii=False))
    else:
        print(encoded, end="")
    return 0 if report["summary"]["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
