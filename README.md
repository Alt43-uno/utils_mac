# utils_mac

Native macOS utilities, built with Swift, AppKit and SwiftUI. No third-party
dependencies.

## Screenshot Booster

A screenshot tool whose defining behaviour is that **every shot you take stays
pinned as a floating thumbnail in the corner of your screen until you dismiss it
yourself** — nothing auto-hides, nothing opens an editor you did not ask for,
and nothing steals your keyboard focus. It comes with a full object-based
annotation editor: freehand, arrows, shapes, text, highlighter, blur, pixelate
and crop, all non-destructive and re-editable after a relaunch.

```bash
cd screenshot_booster
./Scripts/build_app.sh --install --run
```

→ **[Documentation](screenshot_booster/README.md)** ·
[Contributing](CONTRIBUTING.md) · [Changelog](CHANGELOG.md)

Download the universal DMG from [GitHub Releases](https://github.com/Alt43-uno/utils_mac/releases/latest).

Requires macOS 26 (Tahoe) and the Xcode command line tools.

## License

[MIT](LICENSE).
