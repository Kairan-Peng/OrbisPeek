#!/usr/bin/env python3
"""Generate Quick Look declarations and documentation from the shared manifest.

Type associations were adapted from FreeLook (MIT, Copyright 2026 Neo Lee),
commit d3f002589917f51279b49ea8b12b3bb343dd82dc, and checked against local UTType
metadata. See THIRD_PARTY_NOTICES.md. No Launch Services settings are changed.
"""

import argparse
import json
import plistlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "Sources/QuicklookCore/Resources/file-types.json"
EXCLUDED_SUFFIXES = {
    "txt", "text", "pdf", "doc", "docx", "xls", "xlsx",
    "ppt", "pptx", "csv", "svg", "png", "jpg", "jpeg", "mp4", "mov", "mp3",
}
EXCLUDED_UTIS = {
    "public.data", "public.item", "public.content", "public.text", "public.plain-text",
    "public.html", "public.xhtml",
    "public.source-code", "public.xml-based-text", "public.svg-image",
    "public.svg", "com.adobe.pdf", "public.comma-separated-values-text",
    "public.mpeg-2-transport-stream", "public.avchd-mpeg-2-transport-stream",
    "com.apple.logic.exs", "com.adobe.edn", "com.apple.rez-source",
}


def preview_utis(types):
    # Direct public.data requests are bounded text attempts, not an ancestor wildcard.
    return {uti for item in types for uti in item["utis"]} | {"public.data"}


def validate(types):
    seen_ids, seen_suffixes, seen_filenames, declared = set(), {}, {}, set()
    for item in types:
        identifier = item["id"]
        assert identifier not in seen_ids, f"Duplicate group: {identifier}"
        seen_ids.add(identifier)
        assert item["mode"] in {"markdown", "json", "jsonl", "html", "code"}, identifier
        assert item["language"], identifier
        for suffix in item["extensions"]:
            assert suffix and suffix == suffix.lower() and "." not in suffix, suffix
            assert suffix not in EXCLUDED_SUFFIXES, f"System-owned extension: {suffix}"
            assert suffix not in seen_suffixes, f"Duplicate extension: {suffix}"
            seen_suffixes[suffix] = identifier
        for name in item["filenames"]:
            previous = seen_filenames.setdefault(name.lower(), identifier)
            assert previous == identifier, f"Duplicate filename: {name}"
        for uti in item["utis"]:
            assert uti not in EXCLUDED_UTIS and not uti.startswith("dyn."), uti
        for kind in ("imports", "exports"):
            for declaration in item.get(kind, []):
                uti = declaration["identifier"]
                assert uti in item["utis"], f"Unregistered declaration: {uti}"
                assert uti not in declared, f"Duplicate declaration: {uti}"
                declared.add(uti)
                if kind == "exports":
                    assert uti.startswith("org.quicklook.preview."), uti
                assert declaration.get("extensions") or declaration.get("filenames"), uti
                assert not set(declaration.get("extensions", [])) & EXCLUDED_SUFFIXES, uti
                assert not set(declaration.get("extensions", [])) - set(item["extensions"]), uti
                assert not set(declaration.get("filenames", [])) - set(item["filenames"]), uti
    custom = {uti for item in types for uti in item["utis"] if uti.startswith("org.quicklook.preview.")}
    assert not custom - declared, f"Custom UTIs without declarations: {custom - declared}"


def type_declaration(item, declaration):
    tags = {}
    if declaration.get("extensions"):
        tags["public.filename-extension"] = declaration["extensions"]
    if declaration.get("filenames"):
        tags["public.filename"] = declaration["filenames"]
    return {
        "UTTypeIdentifier": declaration["identifier"],
        "UTTypeDescription": item["id"].replace("-", " ").title(),
        "UTTypeConformsTo": declaration.get("conformsTo", ["public.plain-text"]),
        "UTTypeTagSpecification": tags,
    }


def generate_plist(types):
    exported = [type_declaration(item, decl) for item in types for decl in item.get("exports", [])]
    imported = [type_declaration(item, decl) for item in types for decl in item.get("imports", [])]
    return plistlib.dumps({
        "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
        "CFBundleDisplayName": "OrbisPeek Preview",
        "QuicklookAppGroup": "$(QUICKLOOK_APP_GROUP)",
        "QuicklookBuildConfiguration": "$(CONFIGURATION)",
        "CFBundleExecutable": "$(EXECUTABLE_NAME)",
        "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": "$(PRODUCT_NAME)",
        "CFBundlePackageType": "XPC!",
        "CFBundleShortVersionString": "$(MARKETING_VERSION)",
        "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
        "CFBundleDocumentTypes": [{
            "CFBundleTypeName": declaration["UTTypeDescription"],
            "CFBundleTypeRole": "Viewer",
            "LSHandlerRank": "Alternate",
            "LSItemContentTypes": [declaration["UTTypeIdentifier"]],
        } for declaration in exported],
        "UTImportedTypeDeclarations": imported,
        "UTExportedTypeDeclarations": exported,
        "NSExtension": {
            "NSExtensionPointIdentifier": "com.apple.quicklook.preview",
            "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).PreviewViewController",
            "NSExtensionAttributes": {
                "QLIsDataBasedPreview": False,
                "QLSupportedContentTypes": sorted(preview_utis(types)),
                "QLSupportsSearchableItems": False,
            },
        },
    }, fmt=plistlib.FMT_XML, sort_keys=False)


def generate_documentation(types):
    suffix_count = len({suffix for item in types for suffix in item["extensions"]})
    filename_count = len({name.lower() for item in types for name in item["filenames"]})
    semantic_count = len({uti for item in types for uti in item["utis"]})
    uti_count = len(preview_utis(types))
    lines = [
        "# File types and Quick Look routing", "",
        "Generated by `scripts/generate-types.py` from `Sources/QuicklookCore/Resources/file-types.json`. Do not edit this table directly.", "",
        f"The renderer recognizes **{suffix_count} suffixes** across **{len(types)} groups**, plus **{filename_count} case-insensitive filenames**. The extension declares **{uti_count} preview UTIs**: **{semantic_count} semantic types** and a direct `public.data` entry for bounded text attempts. These are recognition/registration counts, **not a claim that Finder has invoked the extension for every suffix**.", "",
        "HTML/HTM/XHTML remain recognizable by the shared renderer but are not registered for this extension; Finder keeps the system HTML preview. TXT, TEXT, PDF, Office, CSV, SVG and media are also left to macOS. `CMakeLists.txt` is an exact-name rendering rule, not a registration for all TXT files.", "",
        "Type associations reuse FreeLook's MIT-licensed UTI mapping work (Neo Lee, 2026; commit `d3f002589917f51279b49ea8b12b3bb343dd82dc`) and the local routing baseline. See `THIRD_PARTY_NOTICES.md`.", "",
        "## Recognition matrix", "",
        "| Group | Suffixes | Exact filenames | Renderer |", "|---|---|---|---|",
    ]
    for item in types:
        suffixes = ", ".join(f"`.{s}`" for s in item["extensions"]) or "—"
        filenames = ", ".join(f"`{name}`" for name in item["filenames"]) or "—"
        lines.append(f"| {item['id']} | {suffixes} | {filenames} | {item['mode']} / `{item['language']}` |")
    lines += ["", "The `.env.*`, `Dockerfile.*` and `Containerfile.*` filename families are recognized after invocation. HCL, Nix, Zig, BibTeX and reStructuredText initially use a plain source view. Other unsupported highlighter grammars also fall back to plain source.", "", "## Registration boundaries", "",
        "The preview whitelist contains exact semantic UTIs plus one explicit `public.data` entry, added by generation rather than the format manifest. Only files whose actual type is directly `public.data` receive that text attempt; this does not catch arbitrary unknown `dyn.*` suffixes by ancestry. The loader must reject unreadable or binary data so the system can retain its fallback presentation. Actual Finder dispatch and fallback require separate acceptance on the target system.", "",
        "The manifest rejects broad base types and HTML preview claims. The generated extension does not claim `public.item`, `public.content`, `public.plain-text`, `public.text`, `public.source-code`, `public.xml-based-text`, `public.html`, `public.xhtml` or concrete `dyn.*` identifiers. Imported declarations add meaningful extension bindings where macOS versions or installed apps leave an otherwise known semantic type incomplete; product-owned exported declarations cover missing text-format routes.", "",
        "No file association defaults are changed by generation or probing. Product declarations have the Viewer role and Alternate handler rank. Finder/provider precedence and third-party registrations still require runtime verification.", "",
    ]
    for item in types:
        if item.get("routingNotes"):
            lines.append(f"- **{item['id']}**: {item['routingNotes']}")
    lines += ["", "## Probe actual files", "", "```sh", "swift scripts/probe-routing.swift --create-fixtures .build/routing/fixtures --output .build/routing/before-install.json", "swift scripts/probe-routing.swift --output .build/routing/samples.json samples", "```", "",
        "The probe records each real file's `URLResourceValues.contentType`, candidate extension UTIs, filename classification and exact whitelist match. It does not install the app, enable the extension, repair Launch Services, or prove which provider rendered a Finder window. After installing/enabling the built app, run the same probe and verify representative files with Space; record the selected provider separately.", "",
        "The initial macOS 27.0.1 baseline was captured in `.build/routing/extension-baseline.json` before installing this project. Examples: `.jsonl/.json5` were dynamic; `.ts/.mts` preferred video types; `.exs` preferred Logic sampler data; `.r` preferred Rez source; `.edn` preferred Adobe DRM metadata. These are machine observations, not universal rules.", "",
    ]
    return "\n".join(lines).encode()


def write_or_check(path, content, check):
    if check:
        if not path.exists():
            raise SystemExit(f"Generated file is stale: {path.relative_to(ROOT)}")
        if path.suffix == ".plist":
            expected = plistlib.loads(content)
            actual = plistlib.loads(path.read_bytes())
            # XcodeGen may reformat and add ordinary build metadata.
            same = all(actual.get(key) == value for key, value in expected.items())
        else:
            same = path.read_bytes() == content
        if not same:
            raise SystemExit(f"Generated file is stale: {path.relative_to(ROOT)}")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail if generated files are stale")
    args = parser.parse_args()
    types = json.loads(MANIFEST.read_text())
    validate(types)
    write_or_check(ROOT / "Config/Preview-Info.plist", generate_plist(types), args.check)
    write_or_check(ROOT / "docs/file-types.md", generate_documentation(types), args.check)
    print(f"{'Checked' if args.check else 'Generated'} {len(types)} groups and {sum(len(t['extensions']) for t in types)} suffixes.")


if __name__ == "__main__":
    main()
