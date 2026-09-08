# Contributing

Thanks for taking a look. Issues and pull requests are welcome.

## Getting set up

You need **macOS 26 (Tahoe)** and the Xcode command line tools
(`xcode-select --install`). There are no other dependencies.

```bash
cd screenshot_booster
./Scripts/build_app.sh --install --run   # build, install to /Applications, launch
./Scripts/run_tests.sh                   # the checks described below
./Scripts/make_dmg.sh                    # a distributable disk image
```

Builds are signed ad-hoc, which means macOS treats every rebuild as a different
application and asks for Screen Recording permission again. The app's own alert
explains this; the short version is to allow it in System Settings and then use
the **Quit and Reopen** button. Always run the copy in `/Applications` rather
than the one in `build/` — two copies of the same bundle identifier each get
their own permission grant, which looks like the app asking forever.

`swift build` may fail on machines without full Xcode: the standalone command
line tools ship a `PackageDescription` module that does not match their SwiftPM
library. `Package.swift` is there so the sources open as a package in Xcode;
`Scripts/build_app.sh` drives `swiftc` directly and always works.

## Tests

`Scripts/run_tests.sh` compiles the sources together with `Tests/` and runs a
set of checks that need no test framework: rendering output, annotation
geometry, hit testing, zoom and pan maths, thumbnail layout, and library
round-trips. Anything that changes the canvas, the renderer or the panel layout
should keep them passing, and new behaviour in those areas is worth a new check.

Storage checks use a unique temporary directory and clean up afterwards. The
test build cannot write to the application's screenshot library or drag cache.
Use `./Scripts/run_tests.sh --rendering-only` for just the rendering and editor
checks.

The parts that cannot be checked this way are the ones that depend on the
compositor — Liquid Glass surfaces do not appear in offscreen renders — and
anything that needs Screen Recording permission. Those need a human looking at
the screen, so please say what you verified by hand in the pull request.

## Style

Match the surrounding code. A few conventions the codebase follows:

- Everything user-facing is `@MainActor`; only expensive isolated work (image
  encoding, file writes) hops to a background task.
- Comments explain *why*, especially where something looks arbitrary — most of
  the odd-looking choices in the drawing code are there because they were
  measured, and the comment says so.
- No files that sprawl. When a type grows past a few hundred lines, its input
  handling or drawing tends to move to a `Type+Aspect.swift` extension.
- No third-party dependencies.

## Commits and pull requests

Use your GitHub `noreply` email for commits. Before pushing, run
`python3 screenshot_booster/Scripts/check_privacy.py` from the repository root.
CI checks the published history for non-noreply identities, Finder metadata,
local home paths, and common secret formats. Do not commit screenshots, local
databases, credentials, or personal data; this check cannot detect every case.

Write commit subjects in the imperative mood ("Add scrolling capture"), and say
in the body why the change is needed rather than restating the diff. For pull
requests, describe what you changed, how you verified it, and — if it touches
drawing — any before and after numbers.
