# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.2] — 2026-09-08

### Fixed

- Remove an orphaned screenshot file if its pin is dismissed while its background
  save is still running.
- Wait for the background write before checking saved-bitmap deletion in tests.

### Added

- Rendering, display-scale, annotation, thumbnail, and library regression checks
  with isolated temporary storage.
- GitHub Actions build, test, and DMG artifacts on macOS 26.
- Repository privacy checks for commit identities, local paths, Finder metadata,
  and common secret formats.
- Project documentation, MIT license, contribution and security policies, and
  issue and pull request templates.
- An English utility catalog with installation and development instructions.

## [1.0.1] — 2026-09-08

- Fix displaced screenshot content and exposed black areas in the editor by
  preserving AppKit's drawing transform.
- Use the current drawing context's pixel density and rebuild cached image tiles
  when the editor's backing properties change.
- Publish a universal DMG for Apple Silicon and Intel.

## [1.0] — 2026-09-07

Initial version of **Screenshot Booster**.

### Capture

- Area, window and full-screen capture behind configurable global shortcuts.
- Selection overlay drawn over a frozen snapshot of every display, so the
  capture UI can never leak into the image.
- Pixel magnifier with live coordinates and colour readout; click a window to
  capture it; Space switches modes; Escape cancels.
- Multiple displays and Retina resolutions throughout.

### Pinned thumbnails

- Floating, non-activating panel that never takes focus and follows the user
  across Spaces and full-screen apps.
- Shots stay until dismissed and are restored after a relaunch.
- Click to edit, two-finger swipe left or ✕ to dismiss, drag to any other app,
  right click for copy, save, reveal and delete.
- Configurable corner, display and card size.

### Editor

- Twelve tools; every annotation is a separate object that can be selected,
  moved, resized, restyled and deleted at any time.
- Non-destructive crop and annotations, persisted per screenshot.
- Zoom from 10% to 1600% by pinch, ⌘-scroll, menu or the status capsule, with
  panning and pointer-anchored zooming.
- Undo/redo, clipboard, save and save-as in PNG or JPEG.

### System integration

- Menu bar item, launch at login, configurable save folder and format,
  automatic clipboard copy, and Screen Recording permission handling that
  explains the relaunch macOS requires.

### Interface

- Liquid Glass throughout: floating control capsules over a transparent,
  blurred editor window, and glass thumbnail cards.
