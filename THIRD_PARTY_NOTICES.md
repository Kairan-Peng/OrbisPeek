# Third-party code and licenses

Quicklook is MIT licensed. Dependencies and adapted source retain their original licenses.

## Adapted Swift and renderer integration

| Project | Pinned revision | License | Reuse and modifications |
|---|---|---|---|
| [FreeLook](https://github.com/neolee/freelook) | `d3f002589917f51279b49ea8b12b3bb343dd82dc` | [MIT](third-party/FreeLook-LICENSE.md) | Bounded text loading, file type mappings, WKWebView integration and Markdown renderer conventions. Added encoding handling, a shared Swift package, bounded JSONL, token-preserving JSON formatting, controlled local resources and a new host. |
| [QLStephenSwift](https://github.com/MyCometG3/QLStephenSwift) | `01125eb446266b235f5ea307e99bd3dfe3a575da` | [MIT](third-party/QLStephenSwift-LICENSE) | Foundation/ICU encoding detection and CF encoding mappings. BOM handling precedes binary detection; reads are bounded and truncation respects encoding units. |

Both license texts are retained in `third-party/`. Copyright notices are retained in adapted source files. Upstream application names, icons, update feeds, analytics and signing identities are not reused.

## JavaScript runtime dependencies

`WebRenderer/package-lock.json` pins dependencies. The build bundles the renderer for the system WebKit engine; Node is only a development tool. The complete runtime dependency list, including transitive dependencies and their licenses, is generated in [WebRenderer/THIRD_PARTY.md](WebRenderer/THIRD_PARTY.md). Full license texts are generated in `Sources/QuicklookUI/Resources/THIRD_PARTY_NOTICES.txt` and must accompany distributed builds. Run `npm --prefix WebRenderer run build` to regenerate both from the locked runtime dependency graph.

The bundled GitHub light/dark syntax styles come from highlight.js; their original theme comments are preserved in `styles.css`. Build and test tools such as esbuild and jsdom are development dependencies and are not included in the application runtime.

## Distribution checklist

The Swift package resources carry `Quicklook-LICENSE.txt`, `FreeLook-LICENSE.txt` and `QLStephenSwift-LICENSE.txt`, alongside the renderer's `THIRD_PARTY_NOTICES.txt`. Both the host and extension include these resource bundles. `scripts/verify-release` checks that every application bundle contains these four texts; the ZIP / DMG verification checks that packaging preserves the full signed file tree.

Keep the root `LICENSE`, this notice, upstream files under `third-party/`, the lockfile and generated notices when redistributing source. Retain the bundled license texts when redistributing compiled applications. A new dependency or copied snippet requires its own license review and attribution before inclusion; the project's MIT license does not replace upstream terms.

No GPL source from QLMarkdown or SourceCodeSyntaxHighlight has been copied into this implementation. Those projects informed the earlier product research; using any of their code later requires a separate license review and notices update.
