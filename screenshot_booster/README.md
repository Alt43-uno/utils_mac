# Screenshot Booster

A native macOS screenshot app built with Swift, AppKit and SwiftUI.

Its defining behaviour: **every screenshot you take stays pinned as a floating
thumbnail in the corner of your screen until you dismiss it yourself.** Nothing
auto-hides, nothing opens an editor you did not ask for, and nothing steals your
keyboard focus.

```
⌃⇧1  capture an area      ⌃⇧2  capture a window      ⌃⇧3  capture the screen
```

---

## Requirements

* macOS 26 (Tahoe) or later — the interface is built on Liquid Glass
  (`glassEffect`, `GlassEffectContainer`), and capture uses ScreenCaptureKit's
  `SCScreenshotManager`
* Xcode command line tools (`xcode-select --install`)

No third-party dependencies.

## Build and run

```bash
./Scripts/build_app.sh --run
```

The script compiles the sources, assembles `build/Screenshot Booster.app`,
renders the app icon, signs the bundle ad-hoc and launches it.

| Option | Effect |
| --- | --- |
| *(none)* | Optimised build for this Mac's architecture |
| `--debug` | Unoptimised build with debug symbols |
| `--universal` | Fat binary for Apple silicon and Intel |
| `--install` | Replace `/Applications/Screenshot Booster.app` |
| `--run` | Launch when the build finishes (the installed copy if `--install` was used) |

For day-to-day use, install rather than running out of `build/`:

```bash
./Scripts/build_app.sh --install --run
```

Keeping a single copy matters more than it sounds: two bundles with the same
identifier at different paths each get their own Screen Recording grant, which
shows up as the app asking for permission over and over.

The app has no Dock icon — look for the camera icon in the menu bar.

Move the bundle to `/Applications` if you want to keep it around; **Launch at
login** works best from there.

### First launch

macOS asks for **Screen Recording** permission the first time you capture. If
the prompt does not appear, enable *Screenshot Booster* under
*System Settings › Privacy & Security › Screen & System Audio Recording*.

Screen Recording permission is bound to the app's code signature. Because local
builds are signed ad-hoc, the signature changes on every rebuild and macOS may
ask again — remove the old entry from the privacy list and re-add the new build
if the capture ever comes back empty.

If you have a signing certificate, use it and the grant survives rebuilds:

```bash
CODESIGN_IDENTITY="Apple Development: you@example.com (XXXXXXXXXX)" ./Scripts/build_app.sh
```

### `swift build`

`Package.swift` is included so the sources open as a package in Xcode. Note that
the standalone Command Line Tools ship a `PackageDescription` module that does
not match their SwiftPM library, so `swift build` may fail with a linker error
on machines without full Xcode. `Scripts/build_app.sh` invokes `swiftc`
directly and always works.

---

## Using it

### Capturing

| Action | Shortcut |
| --- | --- |
| Capture area | `⌃⇧1` |
| Capture window | `⌃⇧2` |
| Capture screen (the one under the pointer) | `⌃⇧3` |

All three are configurable in *Settings › Shortcuts*, and all three are also in
the menu bar menu.

During an area capture:

* **drag** to select, hold **⇧** to constrain to a square
* **click** a window to capture just that window
* **space** toggles between area and window mode
* a **magnifier** follows the pointer with the pixel coordinates and colour
* **esc** or a **right click** cancels

The overlay works from a frozen snapshot of every display, so the selection UI
can never leak into the captured image and the magnifier is always in sync.

### Pinned thumbnails

New shots stack in the corner (bottom left by default), newest closest to the
corner. They stay until you dismiss them and they come back after a restart.

| Gesture | Result |
| --- | --- |
| Click | Open the editor |
| Two-finger swipe left | Dismiss the thumbnail |
| ✕ | Remove the thumbnail |
| Drag | Drop the image into Telegram, Discord, Finder, a browser… |
| Right click | Copy · Save · Save As… · Reveal in Finder · Delete · Clear All |

The swipe follows your fingers and only commits past roughly a third of the
card's width, so a stray gesture springs back. It is read from trackpad scroll
events rather than a drag, which leaves dragging a screenshot out to another app
untouched — and a mouse wheel can never throw a screenshot away.

The panel is a non-activating floating panel: it never takes focus, follows you
across Spaces and full-screen apps, and clicks fall straight through the gaps
between cards.

### Editor

Every annotation is a **separate object**: select it, move it, resize it with
its handles, restyle it or delete it — at any time, including after a restart.

| Tool | Key | | Tool | Key |
| --- | --- | --- | --- | --- |
| Select | `V` | | Highlighter | `H` |
| Freehand | `D` | | Text | `T` |
| Arrow | `A` | | Blur | `B` |
| Line | `L` | | Pixelate | `P` |
| Rectangle | `R` | | Crop | `C` |
| Ellipse | `O` | | Outline area | `S` |

| Command | Shortcut |
| --- | --- |
| Zoom in / out | `⌘+` / `⌘−` |
| Actual size / Zoom to fit | `⌘0` / `⌘9` |
| Undo / Redo | `⌘Z` / `⌘⇧Z` |
| Copy to clipboard | `⌘C` |
| Save / Save As… | `⌘S` / `⇧⌘S` |
| Delete selected object | `⌫` |
| Nudge selection | arrow keys (`⇧` for 10 px) |
| Constrain while drawing | hold `⇧` |
| Close the editor | `⌘W` |

Zooming works the way it does elsewhere on macOS: **pinch** on the trackpad,
**⌘ + scroll**, or the stepper in the status bar, all anchored on the pointer so
the pixel you are looking at stays put. A **two-finger scroll** pans once the
image is bigger than the window, and a **two-finger double tap** toggles between
fitting the window and 100%. Zoom runs from 10% to 1600%; drawing, selecting and
cropping all keep working at any level.

Editing is **non-destructive**: the original bitmap is never modified, so the
crop can be reset and every object stays editable. Closing the editor keeps the
pinned screenshot.

### Settings

* **General** — clipboard, automatic saving, destination folder, PNG/JPEG and
  quality, capture sound, launch at login, whether the pointer is included, and
  whether the app hides its own windows from captures
* **Shortcuts** — record the three global shortcuts, `⌫` clears one
* **Thumbnails** — corner, which display to follow, card size, restore on launch
* **About** — version, Screen Recording status, editor shortcut reference

---

## Architecture

```
Sources/ScreenshotBooster/
├── App/          Entry point, delegate, coordinator, menu bar, main menu
├── Capture/      ScreenCaptureKit, permissions, selection overlay, magnifier
├── Core/         Logging, errors, geometry, image and colour utilities
├── Editor/       View model, renderer, canvas, hit testing, editor window
├── Hotkeys/      Carbon global shortcut registration and key formatting
├── Models/       Screenshot, document, annotation, tools, text layout
├── Settings/     Preferences store, panes, shortcut recorder, launch at login
├── Storage/      Library, paths, export, pasteboard
└── Thumbnails/   Floating panel, stack layout, cards, drag & drop
```

A few decisions worth knowing about:

**One renderer, two destinations.** `AnnotationRenderer` draws in image pixel
space with a top-left origin. The canvas view and the exporter call exactly the
same code, so the preview and the saved file cannot drift apart.

**Non-destructive documents.** A `Screenshot` stores the path to its untouched
bitmap plus an array of `Annotation` values and an optional crop rectangle, all
`Codable`. That is what makes edits survive a relaunch and what keeps undo cheap:
history is a stack of document snapshots, and the (large) bitmap is a shared
reference.

**Liquid Glass, and no solid chrome.** The editor window is transparent: an
`NSVisualEffectView` in `.behindWindow` mode blurs the desktop and whatever
windows are behind it, and the screenshot floats on that with a soft shadow.
The controls are separate glass capsules hovering over the image — tools, style,
history and a prominent Save at the top, one status capsule at the bottom —
rather than bars framing it. The thumbnail panel is the same idea: each shot is
inset in a thin glass frame, with the header, the ✕ badge and the hover caption
on glass too, all inside a `GlassEffectContainer` so neighbouring surfaces merge
and morph as cards come and go.

Liquid Glass samples content inside the window, which is why the behind-window
blur is `NSVisualEffectView` rather than `glassEffect`; the two are doing
different jobs.

**AppKit where it earns its place.** SwiftUI drives the toolbar, thumbnails and
settings. The editing canvas, the capture overlay and the shortcut recorder are
AppKit views, because they need precise mouse handling, custom drawing and event
interception that SwiftUI does not express well.

**Main actor by default.** Everything UI-facing is `@MainActor`; only the
expensive, isolated work — PNG encoding, file writes — hops to a background task.

**Performance details.** The editor redraws in single-digit milliseconds at any
zoom, which took a few specific things:

* The screenshot is rasterised once at exactly its on-screen pixel size and
  blitted 1:1. Core Graphics blits a whole-pixel bitmap almost for free but
  falls into a general resampler for a fractional destination — which is what a
  zoom transform produces at nearly every level, and it costs 10× more.
* That bitmap covers a padded region, so panning reuses it instead of
  re-rasterising every frame.
* Nearest-neighbour when magnifying, smooth when shrinking: measured, each is
  several times faster than the other in its own direction — and nearest is what
  you want for inspecting pixels anyway.
* Only the on-screen part of anything is drawn. The transparency checkerboard
  used to iterate the whole content rectangle, which at 1600% is millions of
  squares per frame; it is now clipped to the window and skipped outright for
  opaque screenshots, which is nearly all of them.
* The drop shadow and border are skipped when the image is larger than the
  window, since there is no visible edge to shade.
* Pinch-zoom keeps its state in the canvas and syncs to the view model a few
  times a second, so a gesture does not re-render the SwiftUI chrome at the
  trackpad's event rate.

The capture overlay puts the frozen display bitmap in a `CALayer` so pointer
movement re-composites instead of redrawing a 5K image; blur and pixelate
results are memoised in an LRU cache and previewed as a placeholder while you
drag; style-slider edits collapse into a single undo step; and library writes
are debounced.

---

## Data locations

| What | Where |
| --- | --- |
| Pinned bitmaps and index | `~/Library/Application Support/com.screenshotbooster.app` |
| Preferences | `defaults read com.screenshotbooster.app` |
| Drag & drop scratch files | temporary directory, cleared at launch and quit |
| Saved screenshots | your chosen folder (Desktop by default) |

Removing the application support folder resets the pinned stack; deleting the
preferences domain resets every setting.
