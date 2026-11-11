# Finder suffix coverage corpus

Generate the complete suffix corpus from the product's authoritative type manifest:

```sh
python3 scripts/make-coverage-fixtures.py
python3 -m unittest discover -s Tests/Acceptance -p test_make_coverage_fixtures.py -v
```

The generator writes these ignored, local acceptance artifacts:

- `.build/finder-coverage/files/`: one UTF-8 text document per declared suffix.
- `.build/finder-coverage/manifest.json`: exact suffix, absolute file path, format
  group, expected renderer mode, visible marker, source template and SHA-256.
- `.build/finder-coverage/extensions.txt`: the complete ordered list of 227 suffixes.
- `.build/finder-coverage/cua-cases.json`: compact `fileName` / `marker` / `extension`
  records for real Finder traversal; all markers appear in the first three lines.

The current manifest has 227 suffixes across 85 suffix-bearing groups. There are
86 total groups; nginx has filename rules only, so it has a template but adds no
suffix case. No suffix is removed because of a possible macOS type conflict.

These are representative **text syntax samples**, not complete applications,
compilable interface products, production configurations, or exhaustive language
conformance tests. The generator never executes source, sends HTTP requests,
installs profiles, builds containers, applies patches, or changes file handlers.
Aliases can share their format's template. Different grammars within a group
have explicit variants, including Cython declarations, Python stubs, Swift
interfaces, Fish/C shell, literate source, EDN, XML schema/project families,
plist families, GLSL shader stages and PowerShell manifests.

Tests parse JSON/JSONL, TOML, INI, XML, plist and Python samples with standard
library parsers (the test suite requires Python 3.11+ for `tomllib`); they also check completeness, hashes, unique visible markers,
representative syntax and dialect-specific structure. The remaining languages
are not validated by every compiler/runtime. File generation and a matching UTI
are not evidence that Finder invoked Quicklook. Each suffix still needs its own
real Finder Space preview showing the correct content marker and provider UI.

The type manifest's routing notes identify known suffix conflicts such as
`.ts`/`.mts` media, `.r` Rez, `.edn` Adobe metadata, `.exs` sampler data and `.fs`
shader/F# ambiguity. Their samples remain in the corpus. A mismatch or failure
must be recorded, not silently skipped or counted as a pass.
