# Contributing to DiskBloom & the macOS utilities

This repository contains independent macOS applications. Keep changes scoped to
the affected application and name it in issues and pull requests.

## DiskBloom

Use macOS 14+ and Swift 6.2+. Work inside `diskbloom/`; keep the scanner, safety
checks, and cloud helper independent of the UI.

```sh
cd diskbloom
./Scripts/build_app.sh --cloud
./Scripts/test.sh
codesign --verify --deep --strict build/DiskBloom.app
```

Build before testing so worker and real-rclone integration checks have their
executables available. Fixtures stay inside `.build`; never test removal on
personal data. For interface work, use `open -n build/DiskBloom.app --args --demo`.
Demo mode does not permit deletion.

Describe manual verification of navigation, previews, collection review, and
cancellation when changing these flows. Permission prompts, live OAuth, Intel,
and minimum macOS compatibility require separate checks; do not infer them from
unit tests. Changes to deletion must cover changed descendants, protected paths,
and overlapping selections. Keep file contents out of scans and exported reports.
See [architecture](diskbloom/docs/ARCHITECTURE.md) and
[feature status](diskbloom/docs/FEATURE_PARITY.md).

DiskBloom tags use `diskbloom-vVERSION`. Match `Resources/Info.plist`, release
notes, and download links. The first release is an Apple Silicon prerelease;
name architecture-specific archives explicitly and include SHA-256 checksums.
Ad hoc signing is not Developer ID notarization. Include signing and feature
limitations in every prerelease. Bundled rclone needs its third-party notices.

## MouseCraft

Use Swift 6.0+ with Xcode or Command Line Tools. The application targets macOS 13+;
Swift Testing requires macOS 14+ on the test machine.

```sh
cd mousecraft
./Scripts/run_tests.sh
./Scripts/build_app.sh --universal
./Scripts/make_installer.sh --no-build
```

`--debug` builds without release optimization; omit `--universal` for just the
current Mac's architecture. Set `MOUSECRAFT_SDK` to choose an installed SDK and
`CODESIGN_IDENTITY` to choose a signing certificate. The toolchain helper can
work around mismatched CLT interfaces using a local copy; system files are not changed.

Core tests cover configuration migration and validation, scroll transformations,
smoothing, gesture routing, button bypass, and AppKit native-event decoding.
Tests never post input events or grant permissions. Delivery to applications,
physical mice, sleep/wake, and permission changes need manual checks; report the
mouse model and what you actually verified.

For installation, quit the running app and use `Scripts/install_app.sh --no-build`.
Run the copy in Applications and grant Accessibility and Input Monitoring to that
copy. Ad hoc rebuilds can require granting permissions again. Always preserve
middle-button down/drag/up events when button processing is disabled.

## Screenshot Booster

Use macOS 26+ and a macOS 26+ SDK.

```sh
cd screenshot_booster
./Scripts/run_tests.sh
./Scripts/build_app.sh --universal
./Scripts/make_dmg.sh --no-build
```

Its rendering, geometry, annotation, recognition, and storage tests use isolated
fixtures. Screen Recording and composited Liquid Glass behavior require manual
checks. See [the application's guide](screenshot_booster/README.md).

## Style and privacy

- Use system frameworks and native platform controls. DiskBloom uses an optional
  rclone executable for cloud storage; document bundled dependencies and licenses.
- Match the surrounding Swift code and explain non-obvious decisions in comments.
- Use meaningful regression checks for input handling, persistence, or rendering changes.
- Use your GitHub `noreply` email for commits.
- Before pushing, run `python3 screenshot_booster/Scripts/check_privacy.py` from the root.
  It checks commit identities, local home paths, Finder metadata, and common secret formats.
- Do not commit personal screenshots, local settings, databases, credentials, or build products.
  Documentation artwork must contain only public app content.

Write imperative commit subjects and explain the problem, resulting behavior,
and validation in pull requests. CI builds each application separately and runs
a repository-wide privacy check.

## Publishing MouseCraft

MouseCraft tags use `mousecraft-vVERSION`, independent of Screenshot Booster's
existing tags. Update `mousecraft/Resources/Info.plist`, the changelog, and the
current download links together. Build and test the exact commit being tagged.

```sh
cd mousecraft
./Scripts/run_tests.sh
./Scripts/build_app.sh --universal
./Scripts/make_installer.sh --no-build
lipo build/MouseCraft.app/Contents/MacOS/MouseCraft -verify_arch arm64
lipo build/MouseCraft.app/Contents/MacOS/MouseCraft -verify_arch x86_64
codesign --verify --deep --strict build/MouseCraft.app
```

Publish the universal DMG, PKG, and `.sha256` file, along with notes describing
compatibility, permissions, signing status, and experimental features. Do not
publish an architecture-specific build under a `universal` filename. Public
releases currently use ad hoc signing and are not notarized.
