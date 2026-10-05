# Security policy

## Reporting a vulnerability

Use **Report a vulnerability** in the repository's Security tab when private
reporting is available. Otherwise, contact the maintainer through an existing
private channel before sharing details. Do not disclose vulnerabilities or
credentials in public issues. Include the application, version, macOS version,
and reproduction steps without sensitive screenshots or logs.

## MouseCraft

- **Accessibility and Input Monitoring:** MouseCraft reads mouse input and changes
  scroll/button events using a Quartz event tap. Assigned actions may generate
  keyboard, mouse, or gesture events, or open an application chosen by the user.
  These permissions are granted manually in System Settings.
- **Local settings:** configuration is stored in
  `~/Library/Application Support/MouseCraft/settings.json`. Export writes to the
  location chosen by the user; import is validated and does not enable processing.
- **Diagnostics:** the UI shows the last input, event counts, and active application.
  Input events are not recorded to files or uploaded.
- **Network:** the application has no telemetry, account, licensing server, or
  network client. macOS handles links to System Settings and opening selected apps.
- **Controls:** processing can be paused from the menu bar. Button gestures can be
  disabled independently so ordinary button events pass through unchanged.

## Screenshot Booster

- **Screen Recording:** ScreenCaptureKit reads screen contents to take captures.
  Images and recognition results stay on the Mac.
- **Local storage:** pinned captures are stored in
  `~/Library/Application Support/com.screenshotbooster.app`; exports use the chosen location.
- **Clipboard:** copied captures are readable by other apps that access the pasteboard.
- **Blur and pixelation:** low-strength effects may leave text legible. Use a filled
  rectangle for secrets and inspect the flattened export before sharing it.
- **Network:** the application does not upload captures or make network requests.

## Release verification and support

Use the newest release **for the affected application**, rather than assuming the
repository's Latest badge refers to both apps. MouseCraft versions are identified
by `mousecraft-vVERSION`; previous Screenshot Booster tags keep their existing names.
The `main` branch may contain unreleased changes.

MouseCraft releases include SHA-256 checksums for the installers. They verify file
integrity, not the publisher's identity. Current app bundles are signed ad hoc,
and installers are not Developer ID notarized. No install script removes macOS
security protections or grants permissions automatically in MouseCraft.
