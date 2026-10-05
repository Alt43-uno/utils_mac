<h1 align="center">utils_mac</h1>

<p align="center">
  <strong>Native utilities for your Mac.</strong><br>
  Smooth mouse control. Better screenshots. Free, local, and open source.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue" alt="MIT license"></a>
  <a href="https://github.com/Alt43-uno/utils_mac/actions/workflows/mousecraft.yml"><img src="https://github.com/Alt43-uno/utils_mac/actions/workflows/mousecraft.yml/badge.svg" alt="MouseCraft build and tests"></a>
  <a href="https://github.com/Alt43-uno/utils_mac/actions/workflows/build.yml"><img src="https://github.com/Alt43-uno/utils_mac/actions/workflows/build.yml/badge.svg" alt="Screenshot Booster build and tests"></a>
</p>

<p align="center">
  <a href="#applications">Applications</a> ·
  <a href="https://github.com/Alt43-uno/utils_mac/releases">Releases</a> ·
  <a href="CONTRIBUTING.md">Contributing</a> ·
  <a href="CHANGELOG.md">Changelog</a>
</p>

## Applications

Each application has its own source, requirements, version, and downloads.
Universal installers include both Apple Silicon and Intel binaries.

| Application | What it does | Requirements | Download |
| :--- | :--- | :--- | :--- |
| **[MouseCraft](mousecraft/README.md)** | Smooth wheel scrolling, button gestures, and profiles for individual apps. | macOS 13+ | [0.2.1 · DMG](https://github.com/Alt43-uno/utils_mac/releases/download/mousecraft-v0.2.1/MouseCraft-0.2.1-universal.dmg) · [PKG](https://github.com/Alt43-uno/utils_mac/releases/download/mousecraft-v0.2.1/MouseCraft-0.2.1-universal.pkg) |
| **[Screenshot Booster](screenshot_booster/README.md)** | Capture, annotate, pin, and recognize text and QR codes. | macOS 26+ | [1.1.0 · DMG](https://github.com/Alt43-uno/utils_mac/releases/download/v1.1.0/ScreenshotBooster-1.1.0-universal.dmg) |

## MouseCraft

<img src="docs/assets/mousecraft.png" alt="MouseCraft app icon" width="96" height="96">

**Make your wheel mouse feel at home on macOS.**

MouseCraft is a free mouse utility with a native settings window and a menu bar
control. No trial, subscription, account, telemetry, or license checks.

- **Smooth scrolling:** choose the feel, speed, direction, and slow-wheel precision.
- **Wheel modifiers:** Shift for horizontal scrolling, Command for zoom, Control
  for faster movement, and Option for precision; each modifier is configurable.
- **Buttons and gestures:** clicks, holds, drags, and scrolling while holding a
  button. Presets for three- and five-button mice, custom shortcuts, and app actions.
- **Independent switches:** turn off button gestures while keeping smooth scrolling.
  Middle-button presses, drags, and releases then reach web canvases unchanged.
- **App profiles:** inherit settings, change scrolling and assignments, or bypass
  processing for a specific application.
- **Native settings:** grouped controls, keyboard navigation with ⌘1–⌘5, launch
  at login, connection diagnostics, and JSON import/export.

### Install MouseCraft

1. [Download the universal DMG](https://github.com/Alt43-uno/utils_mac/releases/download/mousecraft-v0.2.1/MouseCraft-0.2.1-universal.dmg), open it, and drag **MouseCraft** into **Applications**.
   Alternatively, use the [PKG installer](https://github.com/Alt43-uno/utils_mac/releases/download/mousecraft-v0.2.1/MouseCraft-0.2.1-universal.pkg).
2. Eject the disk and launch the copy in Applications. Quit any previous copy
   before updating; your settings are retained.
3. Open **Overview** and grant **Accessibility**
   and **Input Monitoring** in System Settings.
4. Enable MouseCraft. The status must say **Processing is active**.
5. Adjust scrolling. For middle-button panning on a website, turn off
   **Buttons & Gestures → Enable Buttons & Gestures**.

The interface and installer instructions are in English. The menu bar provides pause, settings,
and quit commands; closing the settings window keeps processing active.

**0.2.1 is an early release.** Trackpads, Magic Mouse, and high-resolution wheels
that report continuous input pass through unchanged. Native pinch, Smart Zoom,
and swipes are experimental; interactive Spaces gestures and per-device profiles
are not implemented. See [compatibility and feature status](mousecraft/FEATURE_PARITY.md).

The release is signed ad hoc, without Developer ID notarization. macOS may block
its first launch; follow [Apple's instructions for opening an app you trust](https://support.apple.com/102445).
An update may require re-enabling permissions. No script grants permissions or
removes Gatekeeper protections automatically.

**[Full guide in Russian →](mousecraft/README.md)** ·
**[Release notes →](https://github.com/Alt43-uno/utils_mac/releases/tag/mousecraft-v0.2.1)** ·
**[SHA-256 checksums →](https://github.com/Alt43-uno/utils_mac/releases/download/mousecraft-v0.2.1/MouseCraft-0.2.1-universal.sha256)**

## Screenshot Booster

<img src="docs/assets/screenshot-booster.png" alt="Screenshot Booster app icon" width="88" height="88">

**Capture → annotate → drag into your workflow.**

Capture an area, a window, or a screen and keep it as a floating thumbnail.
Annotate with arrows, shapes, text, highlighting, blur, and pixelation; zoom,
crop, undo, and export as PNG or JPEG. Recognize English and Russian text and
QR codes together using Apple Vision, entirely on your Mac.

Install the [universal DMG](https://github.com/Alt43-uno/utils_mac/releases/download/v1.1.0/ScreenshotBooster-1.1.0-universal.dmg)
in Applications and grant Screen Recording when first capturing.
**Requires macOS 26 Tahoe or later.** This release is also signed ad hoc and is
not notarized.

| Action | Default shortcut |
| :--- | :--- |
| Capture an area | Control + Shift + 1 |
| Capture a window | Control + Shift + 2 |
| Capture the screen under the pointer | Control + Shift + 3 |
| Select an area and recognize text and QR codes | Control + Shift + 4 |

**[Full Screenshot Booster guide →](screenshot_booster/README.md)**

## Build and develop

Install Xcode or Command Line Tools, then clone the repository:

```sh
git clone https://github.com/Alt43-uno/utils_mac.git
cd utils_mac
```

For MouseCraft (Swift 6.0+; tests require macOS 14+):

```sh
cd mousecraft
./Scripts/run_tests.sh
./Scripts/build_app.sh --universal
./Scripts/make_installer.sh --no-build
```

For Screenshot Booster (macOS 26+ SDK):

```sh
cd screenshot_booster
./Scripts/run_tests.sh
./Scripts/build_app.sh --universal
./Scripts/make_dmg.sh --no-build
```

Builds go to each application's `build/`; installers go to `dist/`.
The applications use system frameworks and have no third-party library dependencies.
Read [CONTRIBUTING.md](CONTRIBUTING.md) for verification and release instructions.

```text
utils_mac/
├── mousecraft/           MouseCraft source, tests, installers, and full guide
├── screenshot_booster/   Screenshot Booster source, tests, and full guide
├── docs/assets/          Public app artwork
├── .github/              Per-app CI and issue templates
├── CHANGELOG.md          Release history for both applications
├── CONTRIBUTING.md       Development and release guide
└── SECURITY.md           Permissions, privacy, and vulnerability reporting
```

## Feedback and contributions

[Open an issue](https://github.com/Alt43-uno/utils_mac/issues/new/choose) and
include the application name, version, macOS version, and steps to reproduce.
For MouseCraft, include your mouse model and the connection status.
Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

## License

Both applications are available under the [MIT license](LICENSE).
