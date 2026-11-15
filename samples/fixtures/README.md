# Generated preview fixtures

Recreate/check these fixtures with `python3 scripts/make-fixtures.py`.
Existing files with different contents are deliberately not overwritten.

`manifest.json` records intended reader behavior, source encoding, and hashes.
Binary inputs are intentional rejection cases. TXT remains a system-provider
regression case. HTML/HTM/XHTML use controlled static HTML preview; the historical
`text/system-preview.html` keeps its original bytes and wording as a legacy input,
not a current system-provider expectation. Legacy encodings remain heuristic.

The raster checkerboard images are generated locally with Python's standard
library. The Markdown resource fixture includes blocked remote, parent-path,
symlink, file-URL, SVG, and script examples. HTML fixtures cover static documents,
local raster images and blocked active content/resources. Do not execute fixtures.

Large files are opt-in: `python3 scripts/make-fixtures.py --large` creates ignored
inputs under `.build/fixtures`, never source-controlled 100 MiB / 1 GiB files.
