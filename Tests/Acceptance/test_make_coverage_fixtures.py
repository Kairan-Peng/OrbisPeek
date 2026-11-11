"""Checks the preview corpus, not language-runtime/compiler conformance."""

import ast
import configparser
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import tomllib
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("make_coverage_fixtures", ROOT / "scripts/make-coverage-fixtures.py")
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)


class CoverageFixturesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory()
        cls.output = Path(cls.temporary.name).resolve()
        cls.report = GENERATOR.generate(cls.output)
        cls.cases = {case["extension"]: case for case in cls.report["cases"]}

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def text(self, extension):
        return Path(self.cases[extension]["path"]).read_text(encoding="utf-8")

    def testEveryDeclaredSuffixHasOneCaseAndNoRiskSuffixIsFiltered(self):
        groups = json.loads(GENERATOR.SOURCE.read_bytes())
        declared = [extension for group in groups for extension in group["extensions"]]
        self.assertEqual(len(declared), 227)
        self.assertEqual(self.report["caseCount"], 227)
        self.assertEqual([case["extension"] for case in self.report["cases"]], declared)
        self.assertEqual(self.report["groupCount"], 86)
        self.assertEqual(self.report["coveredGroupCount"], 85)
        self.assertEqual(self.report["filenameOnlyGroups"], ["nginx"])
        self.assertEqual(set(GENERATOR.TEMPLATES), {group["id"] for group in groups})
        self.assertTrue({"ts", "mts", "r", "edn", "exs", "d", "fs"} <= set(self.cases))
        self.assertEqual((self.output / "extensions.txt").read_text().splitlines(), declared)

    def testManifestPathsHashesAndVisibleMarkersDescribeActualFiles(self):
        markers, names = set(), set()
        for case in self.report["cases"]:
            with self.subTest(extension=case["extension"]):
                path = Path(case["path"])
                data = path.read_bytes()
                text = data.decode("utf-8")
                self.assertEqual(path.parent, self.output / "files")
                self.assertEqual(path.name, case["fileName"])
                self.assertEqual(path.suffix, "." + case["extension"])
                self.assertEqual(hashlib.sha256(data).hexdigest(), case["sha256"])
                self.assertNotIn(case["marker"], path.name)
                self.assertIn(case["marker"], "\n".join(text.splitlines()[:3]))
                self.assertNotIn(GENERATOR.PLACEHOLDER, text)
                self.assertLessEqual(len(text.splitlines()), 15)
                self.assertGreater(len(data), 80)
                self.assertNotIn(case["marker"], markers)
                self.assertNotIn(case["fileName"], names)
                markers.add(case["marker"])
                names.add(case["fileName"])
        compact = json.loads((self.output / "cua-cases.json").read_bytes())
        self.assertEqual(len(compact), 227)
        self.assertTrue(all(set(case) == {"fileName", "marker", "extension"} for case in compact))

    def testDataFormatsRemainParseableWithTheirMarkers(self):
        for extension in ("json", "webmanifest"):
            value = json.loads(self.text(extension))
            self.assertEqual(value["coverageMarker"], self.cases[extension]["marker"])
            self.assertIsInstance(value["items"], list)
        for extension in ("jsonl", "ndjson"):
            rows = [json.loads(row) for row in self.text(extension).splitlines()]
            self.assertEqual(rows[0]["coverageMarker"], self.cases[extension]["marker"])
            self.assertEqual(len(rows), 4)
            self.assertIsInstance(rows[1]["details"], dict)
        toml = tomllib.loads(self.text("toml"))
        self.assertEqual(toml["coverage_marker"], self.cases["toml"]["marker"])
        self.assertEqual(toml["server"]["port"], 8080)
        tomllib.loads(self.text("lock"))
        for extension in ("ini", "cfg", "conf", "cnf", "config", "desktop", "gitconfig", "gitmodules", "editorconfig"):
            parser = configparser.ConfigParser()
            text = self.text(extension)
            if extension == "editorconfig":
                text = "[DEFAULT]\n" + text
            parser.read_string(text)
            self.assertGreater(len(parser.sections()), 0)

    def testXMLAndPlistFamiliesUseStructuredDocuments(self):
        for case in self.report["cases"]:
            if case["formatGroup"] not in {"xml", "plist"}:
                continue
            with self.subTest(extension=case["extension"]):
                root = ET.fromstring(Path(case["path"]).read_bytes())
                self.assertGreater(len(root), 0)
                if case["formatGroup"] == "plist":
                    self.assertIsInstance(plistlib.loads(Path(case["path"]).read_bytes()), dict)
        self.assertTrue(ET.fromstring(self.text("xsd")).tag.endswith("schema"))
        self.assertEqual(ET.fromstring(self.text("csproj")).tag, "Project")
        self.assertEqual(ET.fromstring(self.text("pom")).tag.split("}")[-1], "project")

    def testLanguageAndDialectSamplesHaveRepresentativeStructure(self):
        for extension in ("py", "pyw", "pyi"):
            tree = ast.parse(self.text(extension))
            self.assertTrue(any(isinstance(node, ast.ClassDef) for node in tree.body))
        anchors = {
            "md": ["| Name | Enabled |", "- [x]"],
            "jsonc": ["//", '"settings":'], "json5": ["0x2a", "coverageMarker:"],
            "yaml": ["server:", "items:\n  -"], "properties": ["server.port=", "\\u4F60"],
            "gitignore": ["*.log", "!keep.log"], "gitattributes": ["text=auto", "binary"],
            "desktop": ["[Desktop Entry]", "Type=Application"], "env": ["COVERAGE_MARKER=", "SERVER_PORT="],
            "pxd": ["cdef struct", "cpdef int"], "swiftinterface": ["swift-interface-format-version", "public struct"],
            "jsx": ["<article", "items.map"], "tsx": ["interface Item", "<article"],
            "fish": ["function describe --argument-names", "end"], "csh": ["foreach item", "end"],
            "vue": ["<template>", "v-for="], "svelte": ["<script>", "{marker}"], "astro": ["---", "items.map"],
            "graphql": ["type Query", "ID!"], "proto": ['syntax = "proto3"', "message PreviewItem"],
            "make": [".PHONY:", "\t@printf"], "dockerfile": ["FROM ", "CMD ["],
            "patch": ["--- a/", "@@ -1,2 +1,3 @@"], "tf": ['variable "coverage_marker"', "locals {"],
            "zon": [".{", ".items = .{"], "edn": [":coverage-marker", ":tags #{"],
            "lhs": ["> module", "> describe ::"], "mli": ["type preview_item", "val describe"],
            "vh": ["`ifndef", "`define COVERAGE_MARKER"], "psd1": ["@{", "FunctionsToExport"],
            "wat": ["(module", "i32.add"], "comp": ["#version 430", "local_size_x"],
            "sty": ["\\ProvidesPackage", "\\endinput"], "bib": ["@article{", "author ="],
            "litcoffee": ["    marker =", "    describe ="], "http": ["GET https://example.invalid/", "Content-Type:"],
        }
        for extension, values in anchors.items():
            with self.subTest(extension=extension):
                for anchor in values:
                    self.assertIn(anchor, self.text(extension))
        # All groups have syntax-specific base templates, rather than a generic
        # greeting copied under 227 suffixes. Aliases may share their group text.
        normalized = {template.replace(GENERATOR.PLACEHOLDER, "") for template in GENERATOR.TEMPLATES.values()}
        self.assertEqual(len(normalized), 86)


if __name__ == "__main__":
    unittest.main()
