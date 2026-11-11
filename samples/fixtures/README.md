# Generated preview fixtures

Recreate/check these fixtures with `python3 scripts/make-fixtures.py`.
Existing files with different contents are deliberately not overwritten.

`manifest.json` records intended reader behavior, source encoding, and hashes.
Binary inputs are intentional rejection cases. TXT and HTML are system-provider
regression cases. Legacy encoding detection is heuristic; verify displayed text.

The raster checkerboard images are generated locally with Python's standard
library. The Markdown resource fixture includes blocked remote, parent-path,
symlink, file-URL, SVG, and script examples. Do not execute source fixtures.

Large files are opt-in: `python3 scripts/make-fixtures.py --large` creates ignored
inputs under `.build/fixtures`, never source-controlled 100 MiB / 1 GiB files.
