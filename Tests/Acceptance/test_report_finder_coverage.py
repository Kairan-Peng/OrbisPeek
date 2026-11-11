"""Synthetic classifier tests, not observations of Finder or format coverage."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("report_finder_coverage", ROOT / "scripts/report-finder-coverage.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FinderEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="synthetic-finder-report-", dir=ROOT / ".build")
        self.root = Path(self.temporary.name)
        self.cases = []
        for group, suffix in [("swift", "swift"), ("log", "log")]:
            marker = f"QLCOVERAGE_{group.upper()}_{suffix.upper()}"
            path = self.root / f"coverage-{group}.{suffix}"
            path.write_text("// " + marker + "\n")
            self.cases.append({
                "id": f"{group}.{suffix}", "extension": suffix, "fileName": path.name,
                "path": str(path), "formatGroup": group, "expectedMode": "code",
                "marker": marker, "sha256": MODULE.digest(path), "language": group,
            })
        self.manifest = {"schemaVersion": 1, "caseCount": 2, "cases": self.cases}
        self.manifest_path = self.root / "manifest.json"
        self.manifest_path.write_text(json.dumps(self.manifest))

    def tearDown(self):
        self.temporary.cleanup()

    def own_ax(self, case):
        return "\n".join([
            "0 窗口 快速查看, Secondary Actions: Raise",
            f"  1 HTML content Description: {case['fileName']} · Quicklook, URL: quicklook-app://bundle/index.html",
            f"    2 heading {case['fileName']}, Value: 1",
            "    3 toggle button 换行, Value: on",
            "    4 button 复制",
            "    5 button 查找",
            f"    6 text // {case['marker']}",
        ])

    def record(self, case, *, ax=None, provider=None):
        return {
            "caseID": case["id"], "path": case["path"], "sha256": case["sha256"],
            "observedAt": "2026-11-11T00:00:00+08:00", "evidenceType": "cua-ax",
            "observedFileName": case["fileName"],
            "provider": provider or {"kind": "quicklook", "url": MODULE.OWN_URL},
            "axText": ax if ax is not None else self.own_ax(case),
            "_source": {"path": str(self.root / "observations.jsonl"), "line": 1, "index": 0},
        }

    def test_requires_real_title_marker_url_and_toolbar_for_own_pass(self):
        case = self.cases[0]
        self.assertEqual(MODULE.analyze_case(case, [self.record(case)])["status"], "own-provider-content-pass")
        ax = self.own_ax(case).replace("    4 button 复制\n", "")
        self.assertEqual(MODULE.analyze_case(case, [self.record(case, ax=ax)])["status"], "unknown")

    def test_boolean_registration_or_window_claims_cannot_substitute_for_ax(self):
        case = self.cases[0]
        record = self.record(case)
        record.pop("axText")
        record.update({"utiMatched": True, "windowPresent": True, "contentMarkerVisible": True})
        result = MODULE.analyze_case(case, [record])
        self.assertEqual(result["status"], "unknown")
        self.assertTrue(result["inputErrors"])

    def test_expected_marker_in_metadata_or_search_field_is_not_content(self):
        case = self.cases[0]
        ax = self.own_ax(case).replace(
            f"    6 text // {case['marker']}",
            f"    6 search text field 查找文本, Value: {case['marker']}"
        )
        record = self.record(case, ax=ax)
        record["expectedMarker"] = case["marker"]
        self.assertEqual(MODULE.analyze_case(case, [record])["status"], "unknown")

    def test_wrong_file_title_cannot_pass_even_with_expected_marker(self):
        case = self.cases[0]
        ax = self.own_ax(case).replace(case["fileName"], "another-document.swift")
        self.assertEqual(MODULE.analyze_case(case, [self.record(case, ax=ax)])["status"], "unknown")

    def test_finder_window_without_quicklook_window_is_not_a_content_pass(self):
        case = self.cases[0]
        ax = self.own_ax(case).replace("0 窗口 快速查看", "0 标准窗口 files")
        self.assertEqual(MODULE.analyze_case(case, [self.record(case, ax=ax)])["status"], "unknown")

    def test_other_windows_and_focus_echo_cannot_supply_missing_content(self):
        case = self.cases[0]
        ax = self.own_ax(case).replace(case["marker"], "no marker")
        other_window = f"\n10 window TextEdit\n  11 text {case['fileName']}\n  12 text {case['marker']}"
        focus_echo = f"\nThe focused UI element is 6 text {case['marker']}"
        for suffix in [other_window, focus_echo]:
            self.assertEqual(MODULE.analyze_case(case, [self.record(case, ax=ax + suffix)])["status"], "unknown")

    def test_marker_and_toolbar_must_belong_to_same_preview_web_area(self):
        case = self.cases[0]
        ax = self.own_ax(case).replace(f"    6 text // {case['marker']}", f"  6 text // {case['marker']}")
        self.assertEqual(MODULE.analyze_case(case, [self.record(case, ax=ax)])["status"], "unknown")
        ax = self.own_ax(case).replace(case["fileName"], "wrong.swift") + f"\n    7 text {case['fileName']}"
        self.assertEqual(MODULE.analyze_case(case, [self.record(case, ax=ax)])["status"], "unknown")

    def test_native_system_text_requires_explicit_surface_evidence(self):
        case = self.cases[1]
        ax = f"0 窗口 快速查看\n  1 文本输入区 // {case['marker']}\n  2 文本 {case['fileName']}"
        provider = {"kind": "system", "systemEvidence": "native-text-area"}
        record = self.record(case, ax=ax, provider=provider)
        self.assertEqual(MODULE.analyze_case(case, [record])["status"], "system-provider-content-pass")
        record["provider"] = {"kind": "system"}
        self.assertEqual(MODULE.analyze_case(case, [record])["status"], "unknown")

    def test_x_apple_data_preview_url_does_not_prove_system_provider(self):
        case = self.cases[1]
        ax = "\n".join([
            "0 窗口 快速查看",
            f"  1 HTML content Description: {case['fileName']}, URL: x-apple-ql-id2://example/",
            f"  2 text {case['marker']}",
        ])
        provider = {"kind": "system", "systemEvidence": "native-text-area"}
        self.assertEqual(MODULE.analyze_case(case, [self.record(case, ax=ax, provider=provider)])["status"], "unknown")

    def test_native_marker_must_be_in_the_native_text_area(self):
        case = self.cases[1]
        ax = f"0 窗口 快速查看\n  1 文本输入区 unrelated text\n  2 文本 {case['marker']}\n  3 文本 {case['fileName']}"
        provider = {"kind": "system", "systemEvidence": "native-text-area"}
        self.assertEqual(MODULE.analyze_case(case, [self.record(case, ax=ax, provider=provider)])["status"], "unknown")

    def test_checked_content_absence_is_fail_not_missing_observation(self):
        case = self.cases[0]
        record = self.record(case, ax=self.own_ax(case).replace(case["marker"], "preview failed"))
        record.update({"contentObservation": "missing", "failureReason": "Only an icon is visible"})
        self.assertEqual(MODULE.analyze_case(case, [record])["status"], "fail")
        self.assertEqual(MODULE.analyze_case(case, [])["status"], "unknown")

    def test_metadata_icon_title_can_confirm_inspected_file_but_never_content(self):
        case = self.cases[0]
        ax = f"0 窗口 快速查看\n  1 文本 Value: {case['fileName']} 258 字节 上次修改时间：2026年11月11日 , ID: QLAXImageAndText_Text\n  2 图像 预览"
        record = self.record(case, ax=ax, provider={"kind": "unknown"})
        record.update({"contentObservation": "missing", "failureReason": "Only metadata and an icon are visible"})
        self.assertEqual(MODULE.analyze_case(case, [record])["status"], "fail")

    def test_duplicate_records_are_unknown_even_when_both_claim_success(self):
        case = self.cases[0]
        records = [self.record(case), self.record(case)]
        result = MODULE.analyze_case(case, records)
        self.assertEqual(result["status"], "unknown")
        self.assertIn("Duplicate observations", result["inputErrors"][0])

    def test_path_hash_and_fixture_changes_prevent_pass(self):
        case = self.cases[0]
        for key, value in [("path", self.cases[1]["path"]), ("sha256", "0" * 64)]:
            record = self.record(case)
            record[key] = value
            self.assertEqual(MODULE.analyze_case(case, [record])["status"], "unknown")
        Path(case["path"]).write_text("Changed after observation")
        self.assertEqual(MODULE.analyze_case(case, [self.record(case)])["status"], "unknown")

    def test_manifest_rejects_duplicate_ids_suffixes_markers_or_paths(self):
        for key in ["id", "extension", "marker", "path"]:
            manifest = copy.deepcopy(self.manifest)
            manifest["cases"][1][key] = manifest["cases"][0][key]
            if key == "path":
                manifest["cases"][1]["fileName"] = manifest["cases"][0]["fileName"]
            self.manifest_path.write_text(json.dumps(manifest))
            with self.assertRaises(ValueError, msg=key):
                MODULE.load_manifest(self.manifest_path, expected_count=2)

    def test_batch_common_metadata_and_record_sources_are_preserved(self):
        record = self.record(self.cases[0])
        record.pop("_source")
        record.pop("observedAt")
        path = self.root / "batch.jsonl"
        path.write_text(json.dumps({
            "batchID": "synthetic-batch", "observedAt": "2026-11-11T00:00:00+08:00",
            "runMetadata": {"appVersion": "0.1.0", "appBuild": "3"},
            "observations": [record],
        }) + "\n")
        records, sources, errors = MODULE.load_observations([path])
        self.assertEqual(errors, [])
        self.assertEqual(records[0]["observedAt"], "2026-11-11T00:00:00+08:00")
        self.assertEqual(records[0]["runMetadata"]["appBuild"], "3")
        self.assertEqual(sources[0]["sha256"], MODULE.digest(path))

    def test_partial_report_keeps_every_case_and_never_counts_missing_as_pass(self):
        record = self.record(self.cases[0])
        report = MODULE.build_report(self.manifest, [record], manifest_path=self.manifest_path)
        self.assertEqual(len(report["cases"]), 2)
        self.assertEqual(report["summary"]["own-provider-content-pass"], 1)
        self.assertEqual(report["summary"]["unknown"], 1)
        self.assertFalse(report["summary"]["allCasesContentPassed"])
        self.assertEqual(report["summary"]["missingCaseCount"], 1)

    def test_shareable_reports_omit_raw_ax_private_tabs_and_home_username(self):
        case = self.cases[0]
        raw = self.own_ax(case) + "\n  9 标签页 PRIVATE_OTHER_FINDER_TAB\n  10 text " + str(Path.home()) + "/private-documents"
        record = self.record(case, ax=raw)
        record["runMetadata"] = {
            "appVersion": "0.1.0", "appBuild": "3", "architecture": "arm64",
            "appPath": str(Path.home() / "Applications/Quicklook.app"),
            "privateWindowTitle": "PRIVATE_OTHER_FINDER_TAB",
        }
        report = MODULE.build_report(self.manifest, [record], manifest_path=self.manifest_path)
        encoded = json.dumps(report, ensure_ascii=False)
        self.assertNotIn("PRIVATE_OTHER_FINDER_TAB", encoded)
        self.assertNotIn(str(Path.home()), encoded)
        self.assertNotIn("axText", encoded)
        self.assertEqual(report["cases"][0]["evidence"]["rawAXSHA256"], hashlib.sha256(raw.encode()).hexdigest())
        self.assertTrue(report["cases"][0]["evidence"]["quickLookContentExcerpt"])
        self.assertFalse(Path(report["cases"][0]["path"]).is_absolute())
        markdown = MODULE.markdown_report(report)
        self.assertNotIn("PRIVATE_OTHER_FINDER_TAB", markdown)
        self.assertNotIn(str(Path.home()), markdown)

    def test_external_observation_source_paths_are_neutralized(self):
        record = self.record(self.cases[0])
        record["_source"]["path"] = "/Volumes/PrivateClient/observations.jsonl"
        report = MODULE.build_report(self.manifest, [record], manifest_path=self.manifest_path,
                                     observation_sources=[{"path": "/Volumes/PrivateClient/observations.jsonl", "sha256": "0" * 64}])
        encoded = json.dumps(report)
        self.assertNotIn("PrivateClient", encoded)
        self.assertIn("[external]/observations.jsonl", encoded)

    def test_content_pass_does_not_imply_all_cases_used_one_recorded_build(self):
        records = [self.record(case) for case in self.cases]
        metadata = {"macOSVersion": "27.0.1", "osBuild": "26A434", "architecture": "arm64",
                    "appPath": "/Applications/Quicklook.app", "appVersion": "0.1.1", "appBuild": "10"}
        for record in records:
            record["runMetadata"] = dict(metadata)
        report = MODULE.build_report(self.manifest, records, manifest_path=self.manifest_path)
        self.assertTrue(report["summary"]["allCasesVerifiedOnSingleRecordedBuild"])
        records[1]["runMetadata"]["appBuild"] = "9"
        report = MODULE.build_report(self.manifest, records, manifest_path=self.manifest_path)
        self.assertTrue(report["summary"]["allCasesContentPassed"])
        self.assertFalse(report["summary"]["allCasesVerifiedOnSingleRecordedBuild"])
        records[1].pop("runMetadata")
        report = MODULE.build_report(self.manifest, records, manifest_path=self.manifest_path)
        self.assertEqual(report["summary"]["completeRunMetadataCaseCount"], 1)
        self.assertFalse(report["summary"]["allCasesVerifiedOnSingleRecordedBuild"])


class BoundaryPolicyTests(unittest.TestCase):
    """227 synthetic observations exercise policy gating, never Finder coverage."""

    own_ax = FinderEvidenceTests.own_ax
    record = FinderEvidenceTests.record

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="synthetic-boundary-policy-", dir=ROOT / ".build")
        self.root = Path(self.temporary.name)
        definitions = [("typescript", "ts"), ("typescript", "mts"), ("clojure", "edn"), ("elixir", "exs")]
        definitions += [("synthetic", f"case{index:03}") for index in range(223)]
        self.cases = []
        self.records = []
        metadata = {"macOSVersion": "27.0.1", "osBuild": "26A434", "architecture": "arm64",
                    "appPath": "/Applications/Quicklook.app", "appVersion": "0.1.1", "appBuild": "12"}
        for group, suffix in definitions:
            marker = f"QLCOVERAGE_{group.upper()}_{suffix.upper()}"
            path = self.root / f"coverage-{group}.{suffix}"
            path.write_text("// " + marker + "\n")
            case = {"id": f"{group}.{suffix}", "extension": suffix, "fileName": path.name,
                    "path": str(path), "formatGroup": group, "expectedMode": "code",
                    "marker": marker, "sha256": MODULE.digest(path), "language": group}
            self.cases.append(case)
            record = self.record(case)
            record["runMetadata"] = dict(metadata)
            self.records.append(record)
        self.manifest = {"schemaVersion": 1, "caseCount": 227, "cases": self.cases}
        self.manifest_path = self.root / "manifest.json"
        self.manifest_path.write_text(json.dumps(self.manifest))
        self.policy_path = ROOT / "samples/coverage/accepted-limitations.json"
        self.policy = MODULE.load_policy(self.policy_path, self.manifest)
        for index in range(4):
            self.make_metadata_only(index)

    def tearDown(self):
        self.temporary.cleanup()

    def make_metadata_only(self, index):
        case = self.cases[index]
        self.records[index].update({
            "axText": f"0 窗口 快速查看\n  1 文本 Value: {case['fileName']} 258 字节 , ID: QLAXImageAndText_Text\n  2 图像 Description: 预览, ID: QLAXImageAndText_Image",
            "provider": {"kind": "unknown"}, "contentObservation": "missing",
            "failureReason": "The inspected Quick Look contains file metadata and an icon, no document content",
        })

    def report(self, *, use_policy=True, records=None, **kwargs):
        return MODULE.build_report(self.manifest, self.records if records is None else records,
                                   manifest_path=self.manifest_path,
                                   policy=self.policy if use_policy else None, **kwargs)

    def test_default_remains_strict_even_for_the_four_documented_conflicts(self):
        report = self.report(use_policy=False)
        self.assertEqual(report["summary"]["contentPassCount"], 223)
        self.assertEqual(report["summary"]["fail"], 4)
        self.assertEqual(report["summary"]["acceptedLimitationCount"], 0)
        self.assertEqual(report["summary"]["otherFailureCount"], 4)
        self.assertFalse(report["summary"]["allCasesContentPassed"])
        self.assertFalse(report["summary"]["approvedBoundaryGatePassed"])
        self.assertEqual(MODULE.report_exit_code(report), 1)

    def test_explicit_policy_passes_separate_gate_without_relabeling_content(self):
        report = self.report()
        summary = report["summary"]
        self.assertEqual((summary["contentPassCount"], summary["acceptedLimitationCount"],
                          summary["otherFailureCount"], summary["unknown"]), (223, 4, 0, 0))
        self.assertEqual(summary["verifiedObservationCaseCount"], 227)
        self.assertTrue(summary["allCasesHaveSameRecordedBuild"])
        self.assertTrue(summary["approvedBoundaryGatePassed"])
        self.assertFalse(summary["allCasesContentPassed"])
        self.assertFalse(summary["allCasesVerifiedOnSingleRecordedBuild"])
        self.assertTrue(all(case["status"] == "fail" and case["acceptedLimitation"]
                            and case["acceptedLimitationReason"] for case in report["cases"][:4]))
        self.assertEqual(report["boundaryPolicy"]["sha256"], MODULE.digest(self.policy_path))
        self.assertEqual(MODULE.report_exit_code(report), 0)
        markdown = MODULE.markdown_report(report)
        self.assertIn("| 正文内容通过 | 223 |", markdown)
        self.assertIn("| 明确批准的兼容限制 | 4 |", markdown)
        self.assertIn("| 其他内容失败 | 0 |", markdown)
        self.assertIn("全部内容通过：否", markdown)
        self.assertNotIn(str(Path.home()), json.dumps(report))
        self.assertNotIn("axText", json.dumps(report))

    def test_unknown_missing_and_unchecked_cases_cannot_be_accepted(self):
        report = self.report(records=self.records[1:])
        self.assertEqual(report["summary"]["unknown"], 1)
        self.assertFalse(report["cases"][0]["acceptedLimitation"])
        self.assertFalse(report["summary"]["approvedBoundaryGatePassed"])
        self.records[0]["contentObservation"] = "not-checked"
        report = self.report()
        self.assertEqual(report["cases"][0]["status"], "unknown")
        self.assertFalse(report["cases"][0]["acceptedLimitation"])
        self.assertEqual(MODULE.report_exit_code(report), 1)
        self.records[0].pop("axText")
        report = self.report()
        self.assertFalse(report["summary"]["approvedBoundaryGatePassed"])
        self.assertEqual(MODULE.report_exit_code(report), 2)

    def test_other_failures_and_nonmetadata_failures_still_block(self):
        self.make_metadata_only(4)
        report = self.report()
        self.assertEqual(report["summary"]["acceptedLimitationCount"], 4)
        self.assertEqual(report["summary"]["otherFailureCount"], 1)
        self.assertFalse(report["summary"]["approvedBoundaryGatePassed"])
        self.assertEqual(MODULE.report_exit_code(report), 1)
        self.records[0]["axText"] = self.own_ax(self.cases[0]).replace(self.cases[0]["marker"], "preview failed")
        report = self.report()
        self.assertEqual(report["cases"][0]["status"], "fail")
        self.assertFalse(report["cases"][0]["acceptedLimitation"])
        self.assertEqual(report["summary"]["acceptedLimitationCount"], 3)

    def test_mixed_builds_missing_metadata_or_input_errors_block_policy_gate(self):
        self.records[-1]["runMetadata"]["appBuild"] = "11"
        report = self.report()
        self.assertFalse(report["summary"]["allCasesHaveSameRecordedBuild"])
        self.assertFalse(report["summary"]["approvedBoundaryGatePassed"])
        self.records[-1].pop("runMetadata")
        report = self.report()
        self.assertFalse(report["summary"]["approvedBoundaryGatePassed"])
        report = self.report(input_errors=[{"type": "fixture-source-changed"}])
        self.assertFalse(report["summary"]["approvedBoundaryGatePassed"])
        self.assertEqual(MODULE.report_exit_code(report), 2)

    def test_policy_gate_requires_all_227_observations(self):
        self.manifest["cases"] = self.cases[:-1]
        self.manifest["caseCount"] = 226
        self.manifest_path.write_text(json.dumps(self.manifest))
        report = self.report(records=self.records[:-1])
        self.assertEqual(report["summary"]["verifiedObservationCaseCount"], 226)
        self.assertFalse(report["summary"]["approvedBoundaryGatePassed"])

    def test_invalid_policy_is_rejected_instead_of_weakening_the_gate(self):
        base = json.loads(self.policy_path.read_text())
        invalid = []
        for key in ["schemaVersion", "policyID", "policyVersion", "decision", "acceptedLimitations"]:
            policy = copy.deepcopy(base)
            policy.pop(key)
            invalid.append(policy)
        for value in [None, 2, True]:
            policy = copy.deepcopy(base)
            policy["schemaVersion"] = value
            invalid.append(policy)
        for value in [None, "", " "]:
            policy = copy.deepcopy(base)
            policy["acceptedLimitations"][0]["reason"] = value
            invalid.append(policy)
        policy = copy.deepcopy(base)
        policy["acceptedLimitations"][0]["caseID"] = "not-in-manifest.ext"
        invalid.append(policy)
        policy = copy.deepcopy(base)
        policy["acceptedLimitations"].append(dict(policy["acceptedLimitations"][0]))
        invalid.append(policy)
        policy = copy.deepcopy(base)
        policy["decision"]["authority"] = "automatic"
        invalid.append(policy)
        for policy in invalid:
            path = self.root / "invalid-policy.json"
            path.write_text(json.dumps(policy))
            with self.assertRaises(ValueError):
                MODULE.load_policy(path, self.manifest)

    def test_committed_policy_is_exactly_the_four_user_approved_conflicts(self):
        self.assertEqual({entry["caseID"] for entry in self.policy["acceptedLimitations"]},
                         {"typescript.ts", "typescript.mts", "clojure.edn", "elixir.exs"})
        self.assertEqual(self.policy["decision"]["authority"], "user")
        self.assertEqual(self.policy["decision"]["date"], "2026-11-11")


if __name__ == "__main__":
    unittest.main()
