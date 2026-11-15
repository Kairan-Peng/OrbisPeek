"""Checks declaration scope without registering bundles or changing Launch Services."""

import importlib.util
import copy
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("generate_types", ROOT / "scripts/generate-types.py")
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)


class TypeDeclarationTests(unittest.TestCase):
    def testHTMLRemainsRecognizableWithoutClaimingSystemPreview(self):
        groups = json.loads(GENERATOR.MANIFEST.read_bytes())
        html = next(group for group in groups if group["id"] == "html")
        self.assertEqual(html, {
            "id": "html", "language": "html", "mode": "html",
            "extensions": ["html", "htm", "xhtml"], "filenames": [],
            "utis": [],
        })
        GENERATOR.validate(groups)
        current = plistlib.loads(GENERATOR.generate_plist(groups))
        before = plistlib.loads(GENERATOR.generate_plist([group for group in groups if group["id"] != "html"]))
        self.assertEqual(current, before)
        allowed = current["NSExtension"]["NSExtensionAttributes"]["QLSupportedContentTypes"]
        self.assertFalse({"public.html", "public.xhtml"} & set(allowed))
        self.assertEqual(current["CFBundleDisplayName"], "OrbisPeek Preview")
        self.assertTrue(all(item["CFBundleTypeRole"] == "Viewer" and item["LSHandlerRank"] == "Alternate"
                            for item in current["CFBundleDocumentTypes"]))
        self.assertIn("public.xml-based-text", GENERATOR.EXCLUDED_UTIS)

    def testDirectDataIsTheOnlyGeneratedGenericPreviewEntry(self):
        groups = json.loads(GENERATOR.MANIFEST.read_bytes())
        GENERATOR.validate(groups)
        semantic = {uti for item in groups for uti in item["utis"]}
        allowed = set(plistlib.loads(GENERATOR.generate_plist(groups))["NSExtension"]["NSExtensionAttributes"]["QLSupportedContentTypes"])
        self.assertEqual(allowed, semantic | {"public.data"})
        self.assertEqual(len(semantic), 193)
        self.assertEqual(len(allowed), 194)
        self.assertEqual(len(groups), 87)
        self.assertEqual(len({suffix for item in groups for suffix in item["extensions"]}), 230)

    def testManifestCannotAddBroadHTMLOrDynamicPreviewClaims(self):
        groups = json.loads(GENERATOR.MANIFEST.read_bytes())
        for forbidden in ["public.data", "public.item", "public.content", "public.text",
                          "public.html", "public.xhtml", "dyn.ah62d4rv4ge8086xcrf31n5xpr311s5v1qy6xe2u"]:
            with self.subTest(uti=forbidden):
                modified = copy.deepcopy(groups)
                modified[0]["utis"].append(forbidden)
                with self.assertRaises(AssertionError):
                    GENERATOR.validate(modified)

    def testHostOnlyHandlesItsDirectoryAccessRoute(self):
        host = plistlib.loads((ROOT / "Config/App-Info.plist").read_bytes())
        self.assertNotIn("CFBundleDocumentTypes", host)
        self.assertEqual(host.get("UTImportedTypeDeclarations", []), [])
        self.assertEqual(host.get("UTExportedTypeDeclarations", []), [])
        self.assertEqual(host.get("CFBundleURLTypes"), [{
            "CFBundleTypeRole": "Viewer",
            "CFBundleURLName": "org.quicklook.preview.image-access",
            "CFBundleURLSchemes": ["orbispeek"],
        }])

    @unittest.skipUnless(shutil.which("xcodegen"), "XcodeGen is not installed")
    def testHostDirectoryAccessRouteSurvivesActualXcodeGen(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for name in ("App", "Extension", "Config"):
                (directory / name).mkdir()
            shutil.copyfile(ROOT / "project.yml", directory / "project.yml")
            shutil.copyfile(ROOT / "Package.swift", directory / "Package.swift")
            shutil.copyfile(ROOT / "Config/Preview-Info.plist", directory / "Config/Preview-Info.plist")
            result = subprocess.run(["xcodegen", "generate", "--spec", str(directory / "project.yml")],
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            generated = plistlib.loads((directory / "Config/App-Info.plist").read_bytes())
            self.assertNotIn("CFBundleDocumentTypes", generated)
            self.assertNotIn("UTExportedTypeDeclarations", generated)
            project = (directory / "Quicklook.xcodeproj/project.pbxproj").read_text()
            self.assertNotIn("ReaderFindIntent", project)
            self.assertNotIn("UTImportedTypeDeclarations", generated)
            self.assertEqual(generated.get("CFBundleURLTypes"), [{
                "CFBundleTypeRole": "Viewer",
                "CFBundleURLName": "org.quicklook.preview.image-access",
                "CFBundleURLSchemes": ["orbispeek"],
            }])
            preview = plistlib.loads((directory / "Config/Preview-Info.plist").read_bytes())
            allowed = preview["NSExtension"]["NSExtensionAttributes"]["QLSupportedContentTypes"]
            self.assertEqual(len(allowed), 194)
            self.assertIn("public.data", allowed)
            self.assertFalse({"public.html", "public.xhtml", "public.item", "public.content"} & set(allowed))
            self.assertFalse(any(identifier.startswith("dyn.") for identifier in allowed))

    def testLTXFallbackOnlyDeclaresTheUnresolvedTextSuffix(self):
        groups = json.loads(GENERATOR.MANIFEST.read_bytes())
        GENERATOR.validate(groups)
        plist = plistlib.loads(GENERATOR.generate_plist(groups))
        fallback = "org.quicklook.preview.latex-source"
        exported = next(value for value in plist["UTExportedTypeDeclarations"] if value["UTTypeIdentifier"] == fallback)
        self.assertEqual(exported["UTTypeTagSpecification"], {"public.filename-extension": ["ltx"]})
        self.assertEqual(exported["UTTypeConformsTo"], ["public.plain-text"])
        self.assertIn(fallback, plist["NSExtension"]["NSExtensionAttributes"]["QLSupportedContentTypes"])
        document = next(value for value in plist["CFBundleDocumentTypes"] if value["LSItemContentTypes"] == [fallback])
        self.assertEqual(document["CFBundleTypeRole"], "Viewer")
        self.assertEqual(document["LSHandlerRank"], "Alternate")

    def testLTXFallbackPreservesOtherLaTeXAliasesAndExistingTypes(self):
        groups = json.loads(GENERATOR.MANIFEST.read_bytes())
        latex = next(group for group in groups if group["id"] == "latex")
        aliases = ["tex", "sty", "cls", "ltx", "latex"]
        self.assertEqual(latex["extensions"], aliases)
        self.assertEqual(latex["mode"], "code")
        self.assertEqual(latex["language"], "latex")
        self.assertEqual(latex["imports"], [{
            "identifier": "org.tug.tex", "extensions": aliases, "conformsTo": ["public.plain-text"],
        }])
        self.assertTrue({"public.tex", "org.tug.tex", "edu.uo.texshop.tex", "com.barebones.bbedit.tex-source"} <= set(latex["utis"]))
        self.assertEqual(len(latex["exports"]), 1)
        self.assertEqual(latex["exports"][0]["extensions"], ["ltx"])
        plist = plistlib.loads(GENERATOR.generate_plist(groups))
        declared_elsewhere = {
            suffix for value in plist["UTExportedTypeDeclarations"]
            for suffix in value["UTTypeTagSpecification"].get("public.filename-extension", [])
        }
        self.assertFalse(declared_elsewhere & {"tex", "sty", "cls", "latex", "ts", "mts", "exs"})

    def testPHPFallbackOnlyDeclaresTheTwoUnresolvedTextSuffixes(self):
        groups = json.loads(GENERATOR.MANIFEST.read_bytes())
        GENERATOR.validate(groups)
        php = next(group for group in groups if group["id"] == "php")
        self.assertEqual(php["extensions"], ["php", "php3", "php4", "php5", "php7", "phtml"])
        self.assertEqual(php["mode"], "code")
        self.assertEqual(php["language"], "php")
        plist = plistlib.loads(GENERATOR.generate_plist(groups))
        fallback = "org.quicklook.preview.php-source"
        exported = next(value for value in plist["UTExportedTypeDeclarations"] if value["UTTypeIdentifier"] == fallback)
        self.assertEqual(exported["UTTypeTagSpecification"], {"public.filename-extension": ["php5", "php7"]})
        self.assertEqual(exported["UTTypeConformsTo"], ["public.plain-text"])
        self.assertIn(fallback, plist["NSExtension"]["NSExtensionAttributes"]["QLSupportedContentTypes"])
        imported = next(value for value in plist["UTImportedTypeDeclarations"] if value["UTTypeIdentifier"] == "public.php-script")
        self.assertEqual(imported["UTTypeTagSpecification"]["public.filename-extension"], php["extensions"])
        document = next(value for value in plist["CFBundleDocumentTypes"] if value["LSItemContentTypes"] == [fallback])
        self.assertEqual(document["CFBundleTypeRole"], "Viewer")
        self.assertEqual(document["LSHandlerRank"], "Alternate")

    def testConflictingBinaryAndMediaTypesRemainOutsidePreviewWhitelist(self):
        groups = json.loads(GENERATOR.MANIFEST.read_bytes())
        plist = plistlib.loads(GENERATOR.generate_plist(groups))
        allowed = set(plist["NSExtension"]["NSExtensionAttributes"]["QLSupportedContentTypes"])
        protected = {
            "public.item", "public.content", "public.text", "public.plain-text", "public.source-code",
            "public.html", "public.xhtml",
            "public.mpeg-2-transport-stream", "public.avchd-mpeg-2-transport-stream",
            "com.apple.logic.exs", "com.adobe.edn",
        }
        self.assertFalse(allowed & protected)
        self.assertFalse(any(identifier.startswith("dyn.") for identifier in allowed))
        exports = plist["UTExportedTypeDeclarations"]
        suffixes = {suffix for value in exports for suffix in value["UTTypeTagSpecification"].get("public.filename-extension", [])}
        self.assertFalse(suffixes & {"ts", "mts", "exs"})


if __name__ == "__main__":
    unittest.main()
