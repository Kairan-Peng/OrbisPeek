# Changelog

User-visible changes are recorded here. No public release is declared by this development log.

## Unreleased

### Added

- A macOS 15+ Quick Look host and preview extension sharing the same Swift and WebKit renderer.
- Markdown rendering, source highlighting, lossless JSON formatting and bounded JSONL / NDJSON previews.
- A generated registry of document suffixes, exact filenames and UTTypes, with native macOS formats preserved.
- Representative fixtures for every declared suffix and a Finder evidence report tool that checks file hashes, visible content markers and provider evidence. Missing or metadata-only previews remain explicit unknowns or failures.
- Bounded text loading, Unicode BOM handling, legacy-encoding detection and safe fallback for invalid or oversized input.
- Optional read-only directory authorization for local Markdown images, with revocation and sandbox checks.
- Installation diagnostics and built-in sample previews with a receipt from the actual extension when signed and configured.
- Universal Release packaging, embedded third-party licenses, ZIP / DMG integrity verification and local validation reports. Notarization remains an explicit optional operation.
- CI, contribution guidance, security reporting guidance and issue / pull request templates.

### Fixed

- Ambiguous document declarations that could overlap native media or unrelated application formats.
- A product-owned plain-text PHP fallback declaration for `.php5` and `.php7`, which remained unresolved with the imported PHP type on the observed machine. Existing PHP and system-owned format mappings are preserved; Finder behavior requires installation and fresh verification.
- A product-owned plain-text LaTeX fallback declaration limited to `.ltx`, which received a dynamic preferred type and metadata-only Finder preview. Other LaTeX aliases retain their existing declarations; the fix requires fresh Finder verification after installation.
- Sample self-check timing, stale-request handling and confirmation from an unexpected application copy.

### Verified locally

- Individually inspected all 227 suffix fixtures in Finder on macOS 27.0.1 / Apple Silicon with build 12: 220 Quicklook content passes, 3 native text content passes, and 4 explicitly accepted compatibility limitations (`ts`, `mts`, `edn`, `exs`). No missing observations or unexpected failures remained. The four limitations are not content passes.

For current evidence and boundaries, see the [complete Finder report](docs/finder-coverage.md), [installation validation](docs/beta-validation-2026-11-11.md) and [file type list](docs/file-types.md). Registry coverage and successful compilation are separate from an actual Finder preview.
