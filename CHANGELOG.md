# Changelog

User-visible changes are recorded here. Development previews have incomplete platform coverage; notarization status is stated separately for each downloadable package.

## 0.1.1 — 2026-11-15 (development preview)

First downloadable OrbisPeek release, build 1227, for macOS 15+. The Developer ID signed DMG and ZIP contain a Universal (`arm64` + `x86_64`) app. This preview is **not notarized**. See the [installation and permissions guide](docs/installing.md) and [release notes](https://github.com/Kairan-Peng/OrbisPeek/releases/tag/v0.1.1).

### Changed

- Renamed the app to OrbisPeek, with the O-shaped preview mark and the slogan “Press Space. See more.” / “按下空格，看见更多。” Existing bundle identifiers, preferences and resource protocols are retained.
- Simplified the host to an introduction, read-only folder management and an optional extensionless-text switch. First-use folder selection starts at the account's home directory, with another-folder choice retained.
- Kept HTML / HTM / XHTML on the system preview. OrbisPeek is a Finder preview extension; document-opening entry points are removed.
- Replaced the inner filename heading with compact metadata and mode / wrap icons.

### Added

- A macOS 15+ Quick Look host and preview extension sharing the same Swift and WebKit renderer.
- Markdown rendering, source highlighting, lossless JSON formatting and bounded JSONL / NDJSON previews.
- A generated registry of document suffixes, exact filenames and UTTypes, with native macOS formats preserved.
- Representative fixtures for every declared suffix and a Finder evidence report tool that checks file hashes, visible content markers and provider evidence. Missing or metadata-only previews remain explicit unknowns or failures.
- Bounded text loading, Unicode BOM handling, legacy-encoding detection and safe fallback for invalid or oversized input.
- Optional read-only directory authorization for local Markdown images, with revocation and sandbox checks.
- Controlled Markdown `<img>` rendering with bounded local raster images and width / height attributes.
- Extensionless text preview, off by default, for actual `public.data` files. Its shared setting persists across app restarts; strict Unicode loading rejects binary content back to system metadata. Arbitrary unknown dynamic suffixes remain unsupported.
- Universal Release packaging, embedded third-party licenses, ZIP / DMG integrity verification and local validation reports. Notarization remains an explicit optional operation.
- CI, contribution guidance, security reporting guidance and issue / pull request templates.

### Fixed

- Ambiguous document declarations that could overlap native media or unrelated application formats.
- A product-owned plain-text PHP fallback declaration for `.php5` and `.php7`, which remained unresolved with the imported PHP type on the observed machine. Existing PHP and system-owned format mappings are preserved; Finder behavior requires installation and fresh verification.
- A product-owned plain-text LaTeX fallback declaration limited to `.ltx`, which received a dynamic preferred type and metadata-only Finder preview. Other LaTeX aliases retain their existing declarations; the fix requires fresh Finder verification after installation.
- Finder selected-text Copy responder recursion; rendered and source selections copy as plain text.
- Line numbers appearing selected when dragging across source lines, while preserving the plain-text copy projection.

### Removed

- Find, the preview Copy button, Open With / File → Open / ⌘O document-reading entry points, and the host's installation diagnostics / sample UI. Developer validation tools remain available.

### Verified locally

- Individually inspected all 227 suffix fixtures in Finder on macOS 27.0.1 / Apple Silicon with build 12: 220 Quicklook content passes, 3 native text content passes, and 4 explicitly accepted compatibility limitations (`ts`, `mts`, `edn`, `exs`). No missing observations or unexpected failures remained. The four limitations are not content passes.
- Current source: 115 JavaScript, 96 Swift and 56 Python checks pass; generated renderer and type declarations match. Signed build 1226 passed actual Finder off → on → off testing for the optional text preview, app-restart persistence, binary rejection, Markdown rendered / source views and native HTML. See [1226 acceptance](docs/extensionless-opt-in-validation-2026-11-15.md).

For current evidence and boundaries, see the [complete Finder report](docs/finder-coverage.md), [installation validation](docs/beta-validation-2026-11-11.md) and [file type list](docs/file-types.md). Registry coverage and successful compilation are separate from an actual Finder preview.
