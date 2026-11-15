# OrbisPeek brand

- Name: **OrbisPeek** (capital O and P).
- Chinese slogan: **按下空格，看见更多。**
- English slogan: **Press Space. See more.**
- Mark: the approved O-shaped eye / preview window, with a single upward peak inside the opening.
- Palette: midnight teal `#123338`, mint `#68E5C3`, porcelain white.

The name is Orbis + Peek. Orbis contributes the circle / wider-world association; Peek describes quick previewing. The mark is retained from the selected OlymPeek concept; only the final brand name changed.

## Assets

- `orbispeek-icon.png`: macOS app-icon master, with a rounded porcelain / mint tile.
- `orbispeek-mark.png`: transparent standalone mark. The host renders it as a template, using midnight teal in light appearance and mint in dark appearance.
- `../../App/Assets.xcassets`: derived macOS AppIcon sizes, template image, and adaptive brand color.

Regenerate the asset catalog from the checked-in PNG masters on macOS:

```sh
swift scripts/generate-brand-assets.swift
```

The PNG masters were extracted with the built-in image generation tool from the selected concept. Their prompts are retained in [prompts.md](prompts.md). The icons contain no wordmark or slogan so the symbol remains readable at small sizes.

The icon export normalizes transparent padding and clips stray generated edge pixels to a clean rounded tile. To repeat that import from a generated 1254 × 1254 PNG, run `swift scripts/generate-brand-assets.swift --import-icon PATH`. Ordinary regeneration uses the already normalized master without cropping it again.

## Application identity

The visible application and release files use OrbisPeek. The internal Quicklook Xcode project / targets, Swift modules, bundle identifiers, UTIs, URL schemes, App Group and preference / receipt keys remain stable to preserve existing registration and directory grants. The embedded bundle is still `QuicklookPreview.appex`, displayed as **OrbisPeek Preview**.

Historical acceptance reports retain the name and paths that were actually tested. They do not certify a later branded build.
