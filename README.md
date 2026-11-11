# Quicklook

English · [简体中文](README.zh-CN.md)

A lightweight, open-source macOS Quick Look extension. Select a document in Finder and press Space to preview Markdown, JSON / JSONL, configuration files, logs and source code.

Quicklook uses a native Swift host and Quick Look extension, a bounded text loader, and a shared WKWebView renderer. It runs on macOS 15 or newer and ships without Node or Electron.

## Status and formats

This is a development preview. Local Swift and JavaScript checks, signed Universal packaging, installation and core preview flows have been exercised on macOS 27.0.1 / Xcode 27.2 / Apple Silicon. Other macOS versions, Intel hardware, reboot recovery and notarized distribution remain unverified. The current local package has not been submitted for notarization.

The [type registry](docs/file-types.md) recognizes **227 suffixes, 86 format groups and 56 filename rules**. These counts describe recognition, not a claim that every suffix has passed Finder acceptance. Actual routing depends on macOS UTTypes and other installed Quick Look providers.

- Markdown: tables, task lists, highlighted code blocks, and rendered / source views.
- JSON: formatting preserves large integers, duplicate keys, key order and original escapes; invalid JSON falls back to source.
- JSONL / NDJSON: bounded row previews with invalid rows retained and identified.
- YAML, TOML, properties, INI, logs and common source languages: syntax highlighting.
- BOM-aware Unicode loading and best-effort legacy encodings; long lines, display rows and resource sizes are bounded.
- Light / dark appearance, wrapping, line numbers, copying and in-preview search.

TXT, HTML, PDF and Office documents continue to use native macOS preview capabilities. Quicklook does not change their default opening applications or include a separate Office rendering engine.

All **227 suffixes were individually inspected in Finder** on macOS 27.0.1 / Apple Silicon with version **0.1.1 (12)** on 2026-11-11. Actual document content was visible for **223**: 220 through Quicklook and 3 through the native text preview. There were no uninspected cases or unexpected failures.

Four text samples — **`.ts`, `.mts`, `.edn`, `.exs`** — showed file metadata rather than content. These suffixes conflict with video, Adobe data or Logic instruments. The maintainer explicitly chose to preserve those system formats; these cases remain recorded as failures with accepted compatibility limitations, and are never counted as content passes. See the [complete 227-row report](docs/finder-coverage.md), [machine-readable results](docs/finder-coverage.json) and [explicit boundary policy](samples/coverage/accepted-limitations.json).

The [coverage corpus](samples/coverage/README.md) uses representative syntax samples, not private user documents or a claim to validate every content variant. [Reporting rules](docs/finder-coverage-reporting.md) separate actual Finder evidence, type registration, missing observations and accepted limitations. Earlier [local acceptance results](docs/beta-validation-2026-11-11.md) cover installation, directory permissions and rollback.

## Build and run

Requirements: macOS 15+, Xcode 16+ with Swift tools 6.0+, XcodeGen, Python 3.11+ for the full test suite, and Node 24.

```sh
./scripts/build
```

The script installs locked npm dependencies, generates type declarations and the Xcode project, and builds `.build/xcode/Build/Products/Debug/Quicklook.app` with local ad-hoc signing. No Apple developer account is needed for this basic build.

Open the host, then enable Quicklook in **System Settings → General → Login Items & Extensions → Quick Look**. Review competing providers if Finder displays another plugin's preview. The host's document viewer checks rendering; it does not prove Finder selected this extension.

The host's installation / sample check uses system Quick Look. In a correctly signed App Group build, success requires a fresh receipt from the matching installed extension. Basic ad-hoc builds require manual provider confirmation. See [diagnostic boundaries](docs/extension-diagnostics.md).

For build-only work, `./scripts/build --no-register` removes only that build's registration after success. Xcode still briefly registers the output during the build.

## Test and inspect coverage

```sh
npm --prefix WebRenderer ci --no-audit --no-fund
./scripts/test
python3 -m unittest discover -s Tests/Acceptance -p 'test_*.py' -v
python3 scripts/make-coverage-fixtures.py
```

Automated tests cover generated declarations, Swift loading and policy logic, JavaScript rendering, and Python acceptance helpers. Generating fixtures does not open Finder or prove preview coverage. [CI](.github/workflows/ci.yml) also rebuilds generated resources and compiles a Universal app with ad-hoc signing; it does not publish or notarize packages.

For actual WebKit rendering, large-file checks and UTType inspection, follow the [validation plan](docs/validation-plan.md) and [core results](docs/validation-results.md). Route matching, an open Quick Look window and visible document content are separate evidence.

The full suffix check above does not cover all filename-only rules, dotfiles, encodings, file sizes or macOS versions. Those surfaces still require separate verification; recognition alone cannot guarantee Finder dispatch when macOS assigns a broad generic type.

## Local images and security

Document-provided scripts are not executed, and document rendering does not automatically request network resources. Local images are restricted to bounded raster files within the allowed document directory; remote URLs, absolute paths, parent traversal, escaping symlinks and SVG are rejected.

Quick Look normally grants access to the previewed file alone. For local Markdown images, build with your own existing Developer ID and App Group, then grant a read-only folder through the host:

```sh
QUICKLOOK_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
QUICKLOOK_TEAM_ID='TEAMID' \
./scripts/build --directory-access
```

The host need not remain open after the extension receives the grant. Revocation takes effect when the preview is closed and reopened. See [local image access](docs/local-image-access.md) for sandbox limits and verification; no full-disk temporary exception is used.

Report vulnerabilities using [SECURITY.md](SECURITY.md). Share synthetic samples and review diagnostic exports before uploading them.

## Release packaging

```sh
QUICKLOOK_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
QUICKLOOK_TEAM_ID='TEAMID' \
./scripts/package-release

./scripts/verify-release dist/release/Quicklook-0.1.1-macos-universal.manifest.json
```

This builds a Developer ID signed `arm64 + x86_64` Release app and produces ZIP, DMG, SHA-256 and manifest files. Packaging verifies signatures, entitlements, licenses and the unpacked app tree. Signing credentials stay outside the repository. Notarization requires a separate explicit option; ordinary packaging does not upload to Apple.

Universal compilation is not an Intel runtime test. See the [release and rollback guide](docs/releasing.md) and [installation acceptance plan](docs/beta-acceptance.md) before distribution.

## Contributing and licenses

Project owner: [Kairan-Peng](https://github.com/Kairan-Peng). See [CONTRIBUTING.md](CONTRIBUTING.md), the [Code of Conduct](CODE_OF_CONDUCT.md) and [CHANGELOG.md](CHANGELOG.md).

Quicklook's code is [MIT licensed](LICENSE). It adapts MIT code from FreeLook and QLStephenSwift and uses markdown-it, highlight.js and jsonc-parser. Upstream licenses remain intact and ship with both bundles. Exact source revisions, modifications and runtime dependency licenses are recorded in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and the [renderer notices](WebRenderer/THIRD_PARTY.md).
