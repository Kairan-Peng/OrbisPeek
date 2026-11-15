# Contributing

Bug reports, focused changes and format requests are welcome. Please follow the [Code of Conduct](CODE_OF_CONDUCT.md). Report security concerns using [SECURITY.md](SECURITY.md).

## Local setup

Use macOS 15 or newer, Xcode 16 or newer, XcodeGen, Python 3.11 or newer, and Node 24. The Swift package uses Swift tools 6.0. See [README.md](README.md) for installation and the optional Developer ID / App Group build.

```sh
npm --prefix WebRenderer ci --no-audit --no-fund
./scripts/test
python3 -m unittest discover -s Tests/Acceptance -p 'test_*.py' -v
./scripts/build --no-register
```

The default app build uses ad-hoc signing and does not need an Apple developer account. Shared directory authorization and the optional extensionless-text preview switch need your own configured Developer ID and App Group. The switch is off by default and unavailable without that shared configuration. Do not include signing credentials in a contribution. Xcode briefly registers built applications; `--no-register` removes only that output's registration after a successful build.

## Making a change

Keep changes focused and preserve bounded reads, literal document content and sandbox boundaries. Add a small synthetic fixture and a relevant test for behavior changes. Do not upload personal documents or raw diagnostic reports.

- File types: edit `Sources/QuicklookCore/Resources/file-types.json`, then run `python3 scripts/generate-types.py`. This updates the extension declarations and `docs/file-types.md`. Preserve system-owned formats and verify the actual UTType instead of adding broad parent types.
- Renderer: edit `WebRenderer/src/`, then run `npm --prefix WebRenderer run build`. Commit the generated resources and license notices with their sources. Change dependencies through npm so `package-lock.json` stays synchronized.
- Swift: edit `Sources/`, `App/` or `Extension/` as appropriate. Host rendering, extension rendering and Finder provider selection are separate checks.

CI checks generated types, Swift and JavaScript tests, Python acceptance-helper tests, generated renderer resources, and a universal ad-hoc app build. It does not prove Finder routing, App Group permissions, Developer ID signing or notarization. Its macOS runner and toolchain are explicit; official actions are pinned to commit SHAs. Review those pins against the upstream release before updating them.

For Quick Look or resource-access changes, also follow the relevant [validation plan](docs/validation-plan.md), [installation acceptance](docs/beta-acceptance.md) or [local image access](docs/local-image-access.md) checks. Describe what you actually verified, including provider, path, version and any untested platforms. There is no need to restart the system as a routine validation step.

## Licenses and review

Contributions to this project's code are provided under its [MIT license](LICENSE). Keep upstream copyright and license terms intact. Before copying third-party code, record its project URL, exact revision, original license and modifications in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Runtime dependencies must have complete license texts in both application bundles; development tools are not shipped.

Use the pull request template to explain the final behavior and validation. Maintainers may request a smaller change or additional evidence when permissions, routing or large-file behavior changes. Release packaging and rollback are documented in [docs/releasing.md](docs/releasing.md); CI does not publish packages or submit them to Apple.
