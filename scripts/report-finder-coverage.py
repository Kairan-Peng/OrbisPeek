#!/usr/bin/env python3
"""Summarize actual Finder observations without substituting type registration.

The fixture manifest and every observed path/hash must agree. A passing record
requires a complete CUA accessibility snapshot with the file's content marker
and title. This script never opens files in Finder or runs fixture contents.
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import copy
from datetime import date, datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import plistlib
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
STATUSES = (
    "own-provider-content-pass", "system-provider-content-pass", "fail", "unknown",
)
AX_TYPES = {"cua-ax", "cua-ax+screenshot"}
OWN_URL = "quicklook-app://bundle/index.html"
BOUNDARY_CASE_COUNT = 227
SHA256_PATTERN = re.compile(r"^[0-9a-fA-F]{64}$")
TEXT_ROLE = re.compile(
    r"\b(?:text|heading|AXStaticText|AXTextArea|AXHeading)\b|文本|标题|文字",
    re.IGNORECASE,
)
WEB_ROLE = re.compile(r"HTML\s*content|HTML内容|AXWebArea|web\s*area", re.IGNORECASE)
NATIVE_TEXT_ROLE = re.compile(r"AXTextArea|text\s*area|文本输入区", re.IGNORECASE)
AX_NODE = re.compile(r"^([ \t]*)(\d+)\s+(.+)$")


def ax_nodes(ax: str) -> list[dict]:
    """Parse the numbered, indented full AX snapshot, excluding focus echoes."""
    lines = ax.split("\nThe focused UI element", 1)[0].splitlines()
    nodes = []
    for index, line in enumerate(lines):
        match = AX_NODE.match(line)
        if match:
            nodes.append({"start": index, "indent": len(match[1].expandtabs(4)), "label": match[3]})
    for position, node in enumerate(nodes):
        end = nodes[position + 1]["start"] if position + 1 < len(nodes) else len(lines)
        node["value"] = "\n".join(lines[node["start"]:end])
        subtree_end = next((later["start"] for later in nodes[position + 1:]
                            if later["indent"] <= node["indent"]), len(lines))
        node["subtree"] = "\n".join(lines[node["start"]:subtree_end])
    return nodes


def quicklook_windows(ax: str) -> list[str]:
    return [node["subtree"] for node in ax_nodes(ax)
            if re.match(r"(?:窗口|标准窗口|window|standard window|AXWindow)\s+", node["label"], re.IGNORECASE)
            and re.search(r"Quick Look|快速查看|QuickLook", node["label"], re.IGNORECASE)]


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def canonical(path: str | Path) -> Path:
    return Path(path).expanduser().resolve()


def load_manifest(path: Path, expected_count: int = 227) -> dict:
    contents = path.read_bytes()
    manifest = json.loads(contents)
    if not isinstance(manifest, dict) or not isinstance(manifest.get("cases"), list):
        raise ValueError("Fixture manifest must contain a cases array")
    if manifest.get("schemaVersion") != 1:
        raise ValueError("Unsupported fixture manifest schemaVersion")
    cases = manifest["cases"]
    if len(cases) != expected_count or manifest.get("caseCount", len(cases)) != len(cases):
        raise ValueError(f"Expected {expected_count} cases; manifest declares {manifest.get('caseCount')} and contains {len(cases)}")
    unique = {key: set() for key in ["id", "extension", "path", "marker"]}
    for case in cases:
        if not isinstance(case, dict):
            raise ValueError("Every fixture case must be an object")
        for key in ["id", "extension", "fileName", "path", "marker", "sha256"]:
            if not isinstance(case.get(key), str) or not case[key]:
                raise ValueError(f"Fixture case has an invalid {key}: {case}")
        if not Path(case["path"]).is_absolute() or Path(case["path"]).name != case["fileName"]:
            raise ValueError(f"Fixture path/fileName mismatch: {case['id']}")
        if not SHA256_PATTERN.fullmatch(case["sha256"]):
            raise ValueError(f"Invalid fixture hash: {case['id']}")
        if case["marker"] in case["fileName"]:
            raise ValueError(f"Content marker must not appear in the filename: {case['id']}")
        for key, seen in unique.items():
            value = str(canonical(case[key])) if key == "path" else case[key]
            if value in seen:
                raise ValueError(f"Duplicate fixture {key}: {value}")
            seen.add(value)
    manifest["_loadedSHA256"] = hashlib.sha256(contents).hexdigest()
    return manifest


def validate_policy(policy: dict, manifest: dict) -> None:
    """Validate explicit, versioned exceptions without changing content status."""
    if not isinstance(policy, dict) or type(policy.get("schemaVersion")) is not int or policy["schemaVersion"] != 1:
        raise ValueError("Boundary policy must use schemaVersion 1")
    if set(policy) - {"schemaVersion", "policyID", "policyVersion", "decision", "acceptedLimitations", "_loadedSHA256", "_sourcePath"}:
        raise ValueError("Boundary policy contains unsupported fields")
    for key in ["policyID", "policyVersion"]:
        if not isinstance(policy.get(key), str) or not policy[key].strip():
            raise ValueError(f"Boundary policy requires a nonempty {key}")
    decision = policy.get("decision")
    if not isinstance(decision, dict) or decision.get("authority") != "user":
        raise ValueError("Boundary policy requires an explicit user decision")
    if set(decision) != {"authority", "date", "summary"}:
        raise ValueError("Boundary policy decision has invalid fields")
    try:
        date.fromisoformat(decision.get("date", ""))
    except (TypeError, ValueError):
        raise ValueError("Boundary policy requires an ISO decision date") from None
    if not isinstance(decision.get("summary"), str) or not decision["summary"].strip():
        raise ValueError("Boundary policy decision requires a nonempty summary")
    entries = policy.get("acceptedLimitations")
    if not isinstance(entries, list) or not entries:
        raise ValueError("Boundary policy requires an acceptedLimitations array")
    known = {case["id"] for case in manifest["cases"]}
    seen = set()
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("caseID"), str) or entry["caseID"] not in known:
            raise ValueError("Boundary policy contains an unknown or invalid caseID")
        if set(entry) != {"caseID", "reason"}:
            raise ValueError("Boundary policy limitation has invalid fields")
        if entry["caseID"] in seen:
            raise ValueError(f"Duplicate boundary policy caseID: {entry['caseID']}")
        seen.add(entry["caseID"])
        if not isinstance(entry.get("reason"), str) or not entry["reason"].strip():
            raise ValueError(f"Boundary policy requires a nonempty reason: {entry['caseID']}")


def load_policy(path: Path, manifest: dict) -> dict:
    contents = path.read_bytes()
    policy = json.loads(contents)
    validate_policy(policy, manifest)
    policy["_loadedSHA256"] = hashlib.sha256(contents).hexdigest()
    policy["_sourcePath"] = str(path.resolve())
    return policy


def load_observations(paths: list[Path]) -> tuple[list[dict], list[dict], list[dict]]:
    records, sources, errors = [], [], []
    for path in paths:
        try:
            contents = path.read_bytes()
            raw = contents.decode("utf-8")
        except (OSError, UnicodeDecodeError) as error:
            errors.append({"type": "observation-file-unreadable", "path": str(path), "reason": str(error)})
            continue
        sources.append({"path": str(path.resolve()), "sha256": hashlib.sha256(contents).hexdigest()})
        if path.suffix.lower() == ".json":
            try:
                entries = [(1, json.loads(raw))]
            except json.JSONDecodeError as error:
                errors.append({"type": "invalid-observation-json", "path": str(path), "reason": str(error)})
                continue
        else:
            entries = []
            for line, text in enumerate(raw.splitlines(), 1):
                if not text.strip():
                    continue
                try:
                    entries.append((line, json.loads(text)))
                except json.JSONDecodeError as error:
                    errors.append({"type": "invalid-observation-json", "path": str(path), "line": line, "reason": str(error)})
        for line, entry in entries:
            common = {}
            if isinstance(entry, list):
                batch = entry
            elif isinstance(entry, dict) and isinstance(entry.get("observations", entry.get("records")), list):
                batch = entry.get("observations", entry.get("records"))
                common = {key: value for key, value in entry.items() if key not in {"observations", "records"}}
            elif isinstance(entry, dict):
                batch = [entry]
            else:
                errors.append({"type": "invalid-observation-record", "path": str(path), "line": line})
                continue
            for index, item in enumerate(batch):
                if not isinstance(item, dict):
                    errors.append({"type": "invalid-observation-record", "path": str(path), "line": line, "index": index})
                    continue
                record = {**common, **item}
                record["_source"] = {"path": str(path.resolve()), "line": line, "index": index}
                records.append(record)
    return records, sources, errors


def case_identifier(record: dict) -> str | None:
    values = [record[key] for key in ["caseID", "caseId", "id"] if record.get(key) is not None]
    if not values or not all(isinstance(value, str) for value in values) or len(set(values)) != 1:
        return None
    return values[0]


def raw_ax(record: dict) -> tuple[str | None, str | None]:
    evidence = record.get("evidence") if isinstance(record.get("evidence"), dict) else {}
    inline = record.get("axText", evidence.get("axText"))
    ax_file = record.get("axFile", evidence.get("axFile"))
    expected_hash = record.get("axSHA256", evidence.get("axSHA256"))
    if ax_file:
        if not isinstance(ax_file, str):
            return None, "AX file reference is not a path string"
        path = Path(ax_file).expanduser()
        if not path.is_absolute():
            path = Path(record["_source"]["path"]).parent / path
        try:
            contents = path.read_bytes()
        except OSError as error:
            return None, f"AX file is unreadable: {error}"
        if not expected_hash or hashlib.sha256(contents).hexdigest() != str(expected_hash).lower():
            return None, "AX file hash is absent or mismatched"
        try:
            text = contents.decode("utf-8")
        except UnicodeDecodeError:
            return None, "AX file is not UTF-8"
        if inline is not None and inline != text:
            return None, "Inline AX and referenced AX file differ"
    else:
        if not isinstance(inline, str):
            return None, "No raw AX snapshot was recorded"
        text = inline
        if expected_hash and hashlib.sha256(text.encode()).hexdigest() != str(expected_hash).lower():
            return None, "Inline AX hash differs"
    if len(text.encode()) > 2 * 1024 * 1024:
        return None, "AX snapshot exceeds the 2 MiB evidence limit"
    return text, None


def title_candidates(ax: str) -> list[str]:
    candidates = []
    for line in ax.splitlines():
        window = re.search(r'Window:\s*"([^"]*)"', line)
        if window and window[1]:
            candidates.append(window[1])
        web = re.search(r"(?:HTML\s*content|HTML内容|AXWebArea).*?Description:\s*(.*?),\s*URL:", line, re.IGNORECASE)
        if web:
            candidates.append(web[1].removesuffix(" · Quicklook"))
        node = re.match(r"^[\s+~]*\d+\s+(?:heading|标题|text|文本)\s+(.+)$", line, re.IGNORECASE)
        if node:
            text = re.sub(r",\s*(?:Value|ID|Secondary Actions|Help):.*$", "", node[1])
            candidates.append(text.removeprefix("Value: ").removesuffix(" · Quicklook"))
    return sorted(set(candidates))


def has_preview_window(ax: str) -> bool:
    return len(quicklook_windows(ax)) == 1


def file_title_matches(ax: str, filename: str) -> bool:
    nodes = ax_nodes(ax)
    # Web title belongs to the actual preview area. Arbitrary document text
    # equal to the expected filename is not a window title.
    for node in nodes:
        if WEB_ROLE.match(node["label"]) and filename in title_candidates(node["value"]):
            return True
    windows = [node for node in nodes if re.match(
        r"(?:窗口|标准窗口|window|standard window|AXWindow)\s+", node["label"], re.IGNORECASE)]
    if len(windows) == 1:
        root = windows[0]
        child_indents = [node["indent"] for node in nodes if node["indent"] > root["indent"]]
        direct_indent = min(child_indents) if child_indents else None
        if any(node["indent"] == direct_indent and filename in title_candidates(node["value"])
               for node in nodes):
            return True
    # Quick Look's metadata-only icon view has no footer. Its named text node
    # can confirm the inspected file, but never substitutes for actual content.
    return metadata_title_matches(ax, filename)


def metadata_title_matches(ax: str, filename: str) -> bool:
    return any("ID: QLAXImageAndText_Text" in node["label"] and re.search(
        r"(?:^|\s)Value:\s*" + re.escape(filename) + r"(?:\s|$)", node["label"]
    ) for node in ax_nodes(ax))


def has_marker(ax: str, marker: str) -> bool:
    return any(marker in node["value"] and re.match(
        r"(?:text|heading|AXStaticText|AXTextArea|AXHeading)\b|(?:文本|标题|文字)", node["label"], re.IGNORECASE
    ) and not re.search(r"text\s*field|搜索文本|查找文本|文本框|PathTextField|URL:", node["label"], re.IGNORECASE)
               and "ID: QLAXImageAndText_Text" not in node["label"]
               for node in ax_nodes(ax))


def own_web_scopes(ax: str) -> list[str]:
    return [node["subtree"] for node in ax_nodes(ax)
            if WEB_ROLE.match(node["label"]) and re.search(
                r"URL:\s*quicklook-app://bundle/index\.html(?:[?#]\S*)?(?:\s|$|,)", node["label"])]


def own_provider_evidence(ax: str) -> dict:
    webs = own_web_scopes(ax)
    content = webs[0] if len(webs) == 1 else ""
    toolbar = {
        name: any(re.search(r"button|按钮", node["label"], re.IGNORECASE) and name in node["label"]
                  for node in ax_nodes(content))
        for name in ["换行", "复制", "查找"]
    }
    return {"urlMatched": bool(webs), "toolbar": toolbar,
            "confirmed": len(webs) == 1 and all(toolbar.values())}


def observed_at_valid(value) -> bool:
    if not isinstance(value, str):
        return False
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).tzinfo is not None
    except ValueError:
        return False


def analyze_case(case: dict, observations: list[dict]) -> dict:
    result = {
        **case, "status": "unknown", "reasons": [], "inputErrors": [],
        "fixture": {"expectedSHA256": case["sha256"].lower()},
        "observation": None,
    }
    try:
        current_hash = digest(canonical(case["path"]))
        result["fixture"]["actualSHA256"] = current_hash
        if current_hash != case["sha256"].lower():
            result["inputErrors"].append("Fixture content changed after the manifest was generated")
    except OSError as error:
        result["inputErrors"].append(f"Fixture cannot be read: {error}")
    if len(observations) == 0:
        result["reasons"].append("No actual Finder observation recorded")
        return result
    if len(observations) != 1:
        result["inputErrors"].append("Duplicate observations for this case; select one authoritative attempt explicitly")
        result["reasons"].append("Ambiguous observations are not counted as a pass")
        result["observationSources"] = [item["_source"] for item in observations]
        return result
    record = observations[0]
    result["observation"] = record
    path = record.get("path", record.get("filePath"))
    observed_hash = record.get("sha256", record.get("fixtureSHA256"))
    if not isinstance(path, str) or not Path(path).is_absolute() or canonical(path) != canonical(case["path"]):
        result["inputErrors"].append("Observed path does not match this fixture")
    if not isinstance(observed_hash, str) or observed_hash.lower() != case["sha256"].lower():
        result["inputErrors"].append("Observed fixture hash is absent or mismatched")
    if not observed_at_valid(record.get("observedAt")):
        result["inputErrors"].append("Observation has no timezone-qualified timestamp")
    evidence = record.get("evidence") if isinstance(record.get("evidence"), dict) else {}
    evidence_type = record.get("evidenceType", evidence.get("kind"))
    result["evidenceType"] = evidence_type
    if evidence_type not in AX_TYPES:
        result["reasons"].append("A raw CUA accessibility observation is required")
        return result
    ax, error = raw_ax(record)
    if error:
        result["inputErrors"].append(error)
    if ax is not None:
        result["axSHA256"] = hashlib.sha256(ax.encode()).hexdigest()
    if result["inputErrors"]:
        result["reasons"].append("Fixture or observation identity could not be verified")
        return result
    windows = quicklook_windows(ax)
    window_ax = windows[0] if len(windows) == 1 else ""
    titles = title_candidates(window_ax)
    title_matches = file_title_matches(window_ax, case["fileName"])
    claimed_title = record.get("observedFileName")
    if claimed_title is not None and claimed_title != case["fileName"]:
        result["inputErrors"].append("Recorded observedFileName differs from the expected fixture")
        title_matches = False
    window_matches = len(windows) == 1
    marker_visible = has_marker(window_ax, case["marker"])
    own = own_provider_evidence(window_ax)
    nodes = ax_nodes(window_ax)
    metadata_only = (
        metadata_title_matches(window_ax, case["fileName"])
        and any("ID: QLAXImageAndText_Image" in node["label"] for node in nodes)
        and not any(WEB_ROLE.match(node["label"]) or NATIVE_TEXT_ROLE.match(node["label"]) for node in nodes)
    )
    result["evidenceChecks"] = {
        "quickLookWindow": window_matches, "titleFileNameMatches": title_matches,
        "observedTitleCandidates": titles, "contentMarkerVisibleInAX": marker_visible,
        "ownProvider": own, "metadataOnlyPreview": metadata_only,
    }
    if marker_visible and record.get("contentObservation") == "missing":
        result["inputErrors"].append("The record claims missing content but its AX snapshot contains the marker")
        result["reasons"].append("Operator observation contradicts the raw AX content")
        return result
    if not window_matches or not title_matches:
        result["reasons"].append("The expected file's Quick Look window/title was not confirmed")
        return result
    provider = record.get("provider") if isinstance(record.get("provider"), dict) else {}
    kind = provider.get("kind", record.get("providerKind", "unknown"))
    result["provider"] = {"declaredKind": kind, "classification": "unconfirmed"}
    declared_url = provider.get("url")
    if own["confirmed"] and kind == "system":
        result["inputErrors"].append("The record claims a system provider but AX identifies Quicklook")
        result["reasons"].append("Provider claim contradicts the raw AX evidence")
        return result
    if own["confirmed"] and declared_url and not re.fullmatch(re.escape(OWN_URL) + r"(?:[?#]\S*)?", str(declared_url)):
        result["inputErrors"].append("Declared provider URL contradicts Quicklook's AX URL")
        return result
    webs = own_web_scopes(window_ax)
    own_content_visible = len(webs) == 1 and has_marker(webs[0], case["marker"])
    own_title_matches = len(webs) == 1 and file_title_matches(webs[0], case["fileName"])
    result["evidenceChecks"]["ownContentMarkerVisibleInAX"] = own_content_visible
    result["evidenceChecks"]["ownPreviewTitleFileNameMatches"] = own_title_matches
    if own_content_visible and own_title_matches and own["confirmed"]:
        result["status"] = "own-provider-content-pass"
        result["provider"].update({"classification": "quicklook", "observedAXURL": OWN_URL})
        result["reasons"].append("Correct file title, Quicklook AX URL, toolbar and actual content marker confirmed")
        return result
    native = any(NATIVE_TEXT_ROLE.match(node["label"]) for node in ax_nodes(window_ax))
    native_marker = any(NATIVE_TEXT_ROLE.match(node["label"]) and case["marker"] in node["value"]
                        for node in ax_nodes(window_ax))
    system_evidence = provider.get("systemEvidence", record.get("systemEvidence"))
    no_web = not any(WEB_ROLE.match(node["label"]) for node in ax_nodes(window_ax))
    result["evidenceChecks"]["nativeTextArea"] = native
    result["evidenceChecks"]["systemEvidence"] = system_evidence
    if native_marker and no_web and kind == "system" and system_evidence == "native-text-area":
        result["status"] = "system-provider-content-pass"
        result["provider"].update({"classification": "native-system-text", "systemEvidence": system_evidence})
        result["reasons"].append("Correct title and marker in a native text area; no web provider is present")
        result["providerQualification"] = "Native system text surface inferred from AX; renderer bundle identity was not independently observed"
        return result
    missing = record.get("contentObservation") == "missing"
    failure_reason = record.get("failureReason")
    if not marker_visible and missing and isinstance(failure_reason, str) and failure_reason.strip():
        result["status"] = "fail"
        result["reasons"].append("Expected file was inspected but its content marker was not visible: " + failure_reason)
        return result
    if not marker_visible:
        result["reasons"].append("Content marker was not found in actual AX content; absence was not conclusively checked")
    else:
        result["reasons"].append("Content is readable but the provider evidence is insufficient for either pass category")
    return result


def app_snapshot(path: Path | None) -> dict | None:
    if path is None:
        return None
    app = path.expanduser().resolve()
    snapshot = {"path": str(app), "evidence": "report-time bundle snapshot, not per-observation provenance"}
    try:
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        snapshot.update({
            "bundleIdentifier": info.get("CFBundleIdentifier"),
            "version": info.get("CFBundleShortVersionString"), "build": info.get("CFBundleVersion"),
        })
        executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
        snapshot["executableSHA256"] = digest(executable)
    except (OSError, KeyError, ValueError, plistlib.InvalidFileException) as error:
        snapshot["error"] = str(error)
    return snapshot


def machine_snapshot() -> dict:
    snapshot = {"platform": platform.platform(), "macOSVersion": platform.mac_ver()[0], "architecture": platform.machine()}
    try:
        snapshot["osBuild"] = subprocess.check_output(["sw_vers", "-buildVersion"], text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        snapshot["osBuild"] = None
    return snapshot


def public_path(value: str) -> str:
    path = Path(value).expanduser()
    if not path.is_absolute():
        return value
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        try:
            return "~/" + str(path.relative_to(Path.home()))
        except ValueError:
            if str(path).startswith(("/Applications/", "/System/", "/Library/")):
                return value
            return "[external]/" + path.name


def public_report(report: dict) -> dict:
    """Keep raw AX in ignored source files, not in shareable JSON/Markdown."""
    result = copy.deepcopy(report)
    allowed_metadata = {
        "macOSVersion", "osBuild", "architecture", "hardwareModel",
        "appPath", "appVersion", "appBuild",
    }
    for case in result["cases"]:
        record = case.pop("observation", None)
        case["path"] = public_path(case["path"])
        if "evidenceChecks" in case:
            case["evidenceChecks"].pop("observedTitleCandidates", None)
        if not isinstance(record, dict):
            continue
        ax, _ = raw_ax(record)
        excerpt = []
        checks = case.get("evidenceChecks", {})
        if ax and checks.get("quickLookWindow") and checks.get("titleFileNameMatches"):
            windows = quicklook_windows(ax)
            for node in ax_nodes(windows[0] if len(windows) == 1 else ""):
                if (case["fileName"] in title_candidates(node["value"])
                        or metadata_title_matches(node["value"], case["fileName"])
                        or has_marker(node["value"], case["marker"])):
                    excerpt.append(node["value"].strip()[:1000])
        run = record.get("runMetadata") if isinstance(record.get("runMetadata"), dict) else {}
        case["evidence"] = {
            "type": case.get("evidenceType"),
            "source": record.get("_source"),
            "observedAt": record.get("observedAt"),
            "rawAXSHA256": case.get("axSHA256"),
            "quickLookContentExcerpt": excerpt[:8],
            "runMetadata": {key: value for key, value in run.items() if key in allowed_metadata},
        }
        if case["status"] == "fail":
            # Operator notes can contain unrelated window text. Keep the complete
            # note in the original evidence file, not a distributable report.
            case["reasons"] = [
                "Expected file was inspected but its content marker was not visible; detailed operator note is retained in the local raw record"
            ]

    def sanitize(value):
        if isinstance(value, dict):
            return {key: sanitize(item) for key, item in value.items()}
        if isinstance(value, list):
            return [sanitize(item) for item in value]
        if isinstance(value, str):
            if value.startswith("/"):
                value = public_path(value)
            value = value.replace(str(ROOT), ".").replace(str(Path.home()), "~")
            return re.sub(r"/Users/[^/\s\"',;:)]+", "~", value)
        return value
    return sanitize(result)


def build_report(manifest: dict, records: list[dict], *, manifest_path: Path,
                 observation_sources: list[dict] | None = None,
                 input_errors: list[dict] | None = None, app: Path | None = None,
                 policy: dict | None = None) -> dict:
    if policy is not None:
        validate_policy(policy, manifest)
    errors = list(input_errors or [])
    lookup = {case["id"]: case for case in manifest["cases"]}
    indexed = defaultdict(list)
    for record in records:
        identifier = case_identifier(record)
        if identifier not in lookup:
            errors.append({"type": "unknown-or-invalid-case-id", "caseID": identifier, "source": record.get("_source")})
            continue
        indexed[identifier].append(record)
    cases = [analyze_case(case, indexed[case["id"]]) for case in manifest["cases"]]
    policy_entries = {entry["caseID"]: entry for entry in policy["acceptedLimitations"]} if policy else {}
    for case in cases:
        case["acceptedLimitation"] = False
        entry = policy_entries.get(case["id"])
        checks = case.get("evidenceChecks", {})
        if (entry and case["status"] == "fail" and not case["inputErrors"]
                and checks.get("metadataOnlyPreview") and checks.get("contentMarkerVisibleInAX") is False):
            case["acceptedLimitation"] = True
            case["acceptedLimitationReason"] = entry["reason"]
        for reason in case["inputErrors"]:
            errors.append({"type": "invalid-case-evidence", "caseID": case["id"], "reason": reason})
    source_check = None
    if manifest.get("sourceManifest") and manifest.get("sourceManifestSHA256"):
        source = Path(manifest["sourceManifest"])
        if not source.is_absolute():
            source = ROOT / source
        source_check = {"path": str(source), "expectedSHA256": manifest["sourceManifestSHA256"]}
        try:
            source_check["actualSHA256"] = digest(source)
            source_check["matches"] = source_check["actualSHA256"] == source_check["expectedSHA256"]
        except OSError as error:
            source_check.update({"matches": False, "error": str(error)})
        if not source_check["matches"]:
            errors.append({"type": "source-type-manifest-changed", "evidence": source_check})
    counts = {status: sum(case["status"] == status for case in cases) for status in STATUSES}
    passes = counts[STATUSES[0]] + counts[STATUSES[1]]
    record_builds = Counter()
    for record in records:
        metadata = record.get("runMetadata") if isinstance(record.get("runMetadata"), dict) else {}
        if metadata.get("appVersion") is not None and metadata.get("appBuild") is not None:
            record_builds[(str(metadata["appVersion"]), str(metadata["appBuild"]))] += 1
    run_keys = ("macOSVersion", "osBuild", "architecture", "appPath", "appVersion", "appBuild")
    complete_case_runs = []
    for case in cases:
        record = case.get("observation") or {}
        metadata = record.get("runMetadata") if isinstance(record.get("runMetadata"), dict) else {}
        if all(isinstance(metadata.get(key), str) and metadata[key].strip() for key in run_keys):
            complete_case_runs.append(tuple(metadata[key] for key in run_keys))
    run_set = set(complete_case_runs)
    all_passed = passes == len(cases) and not errors
    same_recorded_build = len(complete_case_runs) == len(cases) and len(run_set) == 1
    observed_cases = sum(
        bool(case.get("axSHA256")) and not case["inputErrors"]
        and case.get("evidenceChecks", {}).get("quickLookWindow", False)
        and case.get("evidenceChecks", {}).get("titleFileNameMatches", False)
        for case in cases
    )
    accepted = sum(case["acceptedLimitation"] for case in cases)
    approved_gate = (policy is not None and not errors and len(cases) == BOUNDARY_CASE_COUNT
                     and observed_cases == len(cases) and same_recorded_build
                     and passes + accepted == len(cases))
    policy_snapshot = None
    if policy is not None:
        policy_content = {key: value for key, value in policy.items() if not key.startswith("_")}
        policy_snapshot = {
            **policy_content, "path": policy.get("_sourcePath"),
            "sha256": policy.get("_loadedSHA256") or hashlib.sha256(
                json.dumps(policy_content, sort_keys=True, ensure_ascii=False).encode()).hexdigest(),
        }
    report = {
        "schemaVersion": 1, "generatedAt": datetime.now(timezone.utc).isoformat(),
        "scope": "Actual Finder CUA accessibility observations; UTType recognition and window existence alone never count as content passes.",
        "fixtureManifest": {"path": str(manifest_path.resolve()), "sha256": manifest.get("_loadedSHA256") or digest(manifest_path),
                            "sourceTypeManifest": source_check,
                            **{key: manifest.get(key) for key in ["fixtureNature", "caseCount", "groupCount", "coveredGroupCount", "filenameOnlyGroups"]}},
        "reportMachine": machine_snapshot(), "reportTimeInstallation": app_snapshot(app),
        "boundaryPolicy": policy_snapshot,
        "observedBuilds": [{"version": version, "build": build, "recordCount": count}
                           for (version, build), count in sorted(record_builds.items())],
        "observationFiles": observation_sources or [], "validationErrors": errors,
        "summary": {"caseCount": len(cases), "recordedCaseCount": sum(bool(indexed[case["id"]]) for case in cases),
                    **counts, "contentPassCount": passes,
                    "acceptedLimitationCount": accepted,
                    "otherFailureCount": counts["fail"] - accepted,
                    "verifiedObservationCaseCount": observed_cases,
                    "missingCaseCount": sum(not indexed[case["id"]] for case in cases),
                    "allCasesContentPassed": all_passed,
                    "completeRunMetadataCaseCount": len(complete_case_runs),
                    "allCasesVerifiedOnSingleRecordedBuild": all_passed and same_recorded_build,
                    "allCasesHaveSameRecordedBuild": same_recorded_build,
                    "approvedBoundaryGatePassed": approved_gate,
                    "inputValidationPassed": not errors},
        "limitations": [
            "Each fixture is a small representative text sample, not every possible file bearing that suffix.",
            "Native system text classification uses the recorded native AX surface and excludes web providers; it is not a renderer bundle identity attestation.",
            "Missing observations, missing raw AX, mismatched paths/hashes/titles and unconfirmed providers are never counted as passes.",
            "A report-time app snapshot does not prove the build used for earlier observations; per-batch runMetadata records that provenance.",
            "No system reboot, cross-version OS run, or Intel hardware execution is implied by this report.",
            "Full raw AX remains in ignored observation files. Shareable reports contain only current Quick Look title/content excerpts, evidence digests and local relative references.",
            "An explicitly supplied versioned policy can accept observed metadata-only compatibility limits for a separate boundary gate; these remain fail and never become content passes.",
        ],
        "cases": cases,
    }
    return public_report(report)


def markdown_report(report: dict) -> str:
    def cell(value) -> str:
        return str(value).replace("|", r"\|").replace("\n", " ")
    summary = report["summary"]
    policy = report["boundaryPolicy"]
    policy_description = (f"{cell(policy['policyID'])} / {cell(policy['policyVersion'])}；"
                          f"决定日期 {cell(policy['decision']['date'])}；来源 {cell(policy['path'])}；"
                          f"SHA-256 {cell(policy['sha256'])}。") if policy else "未启用。"
    lines = [
        "# Finder 逐后缀真实预览验收", "",
        f"生成时间：{report['generatedAt']}。本报告只根据保存的 CUA 原始 AX 证据分类，不使用 UTType 命中率代替预览结果。", "",
        f"输入校验：{'通过' if summary['inputValidationPassed'] else '失败，需先修正证据歧义或文件变更'}。"
        f"全部内容通过：{'是' if summary['allCasesContentPassed'] else '否'}。", "",
        f"已批准兼容边界验收：{'通过' if summary['approvedBoundaryGatePassed'] else '未通过' if report['boundaryPolicy'] else '未启用政策'}。"
        "兼容限制继续保留原始 fail 状态，不计为正文内容通过。", "",
        "| 验收结果 | 数量 |", "|---|---:|",
        f"| 正文内容通过 | {summary['contentPassCount']} |",
        f"| 明确批准的兼容限制 | {summary['acceptedLimitationCount']} |",
        f"| 其他内容失败 | {summary['otherFailureCount']} |",
        f"| 未知 | {summary['unknown']} |", "",
        "| 分类 | 数量 |", "|---|---:|",
        *[f"| {status} | {summary[status]} |" for status in STATUSES],
        f"| 总 case | {summary['caseCount']} |", f"| 缺少观察记录 | {summary['missingCaseCount']} |", "",
        "## 运行与证据", "",
        "报告机器快照：" + cell(json.dumps(report["reportMachine"], ensure_ascii=False)) + "。",
        "报告时安装快照：" + cell(json.dumps(report["reportTimeInstallation"], ensure_ascii=False)) + "。",
        "逐批记录的版本 / build：" + cell(json.dumps(report["observedBuilds"], ensure_ascii=False)) + "。",
        "显式兼容边界政策：" + policy_description,
        "安装快照不自动证明早先每条观察使用相同构建。机器、安装信息如记录在各批 runMetadata 中，以各条原始记录为准。", "",
        f"具备完整运行元数据的 case：{summary['completeRunMetadataCaseCount']} / {summary['caseCount']}。"
        f"全部 case 在同一已记录构建与系统上通过：{'是' if summary['allCasesVerifiedOnSingleRecordedBuild'] else '否'}。", "",
        "## 逐项结果", "",
        "| # | 后缀 | 格式组 | 原始结果 | 已批准兼容限制 | 文件 | 原因 |", "|---:|---|---|---|---|---|---|",
    ]
    for index, case in enumerate(report["cases"], 1):
        reasons = case["inputErrors"] + case["reasons"]
        limitation = case.get("acceptedLimitationReason", "—") if case["acceptedLimitation"] else "—"
        lines.append(f"| {index} | .{cell(case['extension'])} | {cell(case.get('formatGroup', ''))} | {case['status']} | {cell(limitation)} | {cell(case['fileName'])} | {cell('; '.join(reasons))} |")
    if report["validationErrors"]:
        lines += ["", "## 输入校验错误", ""]
        lines += ["- " + cell(json.dumps(error, ensure_ascii=False)) for error in report["validationErrors"]]
    lines += ["", "## 边界", "", *["- " + item for item in report["limitations"]], ""]
    return "\n".join(lines)


def report_exit_code(report: dict) -> int:
    if report["validationErrors"]:
        return 2
    return 0 if (report["summary"]["allCasesContentPassed"] or report["summary"]["approvedBoundaryGatePassed"]) else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=ROOT / ".build/finder-coverage/manifest.json")
    parser.add_argument("--observations", type=Path, nargs="+", required=True, help="JSONL records, JSON arrays, or batches with an observations array")
    parser.add_argument("--expected-count", type=int, default=227)
    parser.add_argument("--app", type=Path, help="Read current installed bundle metadata; not a substitute for per-observation build metadata")
    parser.add_argument("--policy", type=Path, help="Explicit versioned approval of observed metadata-only compatibility limits; never changes content-pass status")
    parser.add_argument("--json-output", type=Path, default=ROOT / ".build/finder-coverage/results.json")
    parser.add_argument("--markdown-output", type=Path, default=ROOT / ".build/finder-coverage/results.md")
    args = parser.parse_args()
    try:
        manifest = load_manifest(args.manifest, args.expected_count)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        parser.exit(2, f"Invalid fixture manifest: {error}\n")
    try:
        policy = load_policy(args.policy, manifest) if args.policy else None
    except (OSError, ValueError, json.JSONDecodeError) as error:
        parser.exit(2, f"Invalid boundary policy: {error}\n")
    records, sources, errors = load_observations(args.observations)
    report = build_report(manifest, records, manifest_path=args.manifest,
                          observation_sources=sources, input_errors=errors, app=args.app, policy=policy)
    for path, text in [
        (args.json_output, json.dumps(report, ensure_ascii=False, indent=2) + "\n"),
        (args.markdown_output, markdown_report(report)),
    ]:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    print(json.dumps({**report["summary"], "validationErrorCount": len(report["validationErrors"]),
                      "jsonReport": str(args.json_output.resolve()),
                      "markdownReport": str(args.markdown_output.resolve())}, ensure_ascii=False))
    return report_exit_code(report)


if __name__ == "__main__":
    raise SystemExit(main())
