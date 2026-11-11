"""Checks declaration scope without registering bundles or changing Launch Services."""

import importlib.util
import json
from pathlib import Path
import plistlib
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("generate_types", ROOT / "scripts/generate-types.py")
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)


class TypeDeclarationTests(unittest.TestCase):
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
        self.assertEqual(sum(len(group["extensions"]) for group in groups), 227)

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
            "public.data", "public.content", "public.text", "public.plain-text", "public.source-code",
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
