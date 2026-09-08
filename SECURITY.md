# Security policy

## Reporting a vulnerability

Please do not disclose vulnerabilities in public issues. Use **Report a
vulnerability** in the repository's Security tab when private reporting is
available. Otherwise, contact the maintainer through an existing private
channel before sharing details. Include the macOS version, the build you are
running, and the steps to reproduce, without attaching credentials or sensitive
screenshots.

## What this software touches

Screenshot Booster is worth a moment's thought because of what it has access to:

- **Screen Recording permission.** The app can read the contents of your screen,
  which is inherent to taking screenshots. Captures are made with
  ScreenCaptureKit and never leave your machine.
- **Local storage.** Pinned screenshots are written to
  `~/Library/Application Support/com.screenshotbooster.app`, and files you
  export go wherever you choose. Nothing is uploaded anywhere; the app makes no
  network requests at all.
- **Clipboard.** Captures are copied to the general pasteboard when that setting
  is enabled, which makes them readable by other applications.
- **Blur and pixelate are not redaction.** They are applied when the image is
  flattened, so an exported file does not contain the original pixels — but a
  low blur radius over small text can still be legible. For secrets, use a
  filled rectangle.

## Supported versions

The latest published GitHub release is the supported version. The `main` branch
may contain changes that have not been released yet.
