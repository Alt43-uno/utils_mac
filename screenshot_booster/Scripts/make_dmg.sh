#!/bin/bash
#
# Packages Screenshot Booster into a distributable disk image.
#
#   ./Scripts/make_dmg.sh              universal build, compressed .dmg in dist/
#   ./Scripts/make_dmg.sh --fast       skip the Intel slice (this Mac only)
#   ./Scripts/make_dmg.sh --no-build   package whatever is already in build/
#   ./Scripts/make_dmg.sh --open       reveal the finished image in Finder
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Screenshot Booster"
VOLUME_NAME="Screenshot Booster"
APP_BUNDLE="$ROOT/build/$APP_NAME.app"
DIST_DIR="$ROOT/dist"

BUILD=1
UNIVERSAL=1
REVEAL=0

for argument in "$@"; do
    case "$argument" in
        --fast) UNIVERSAL=0 ;;
        --no-build) BUILD=0 ;;
        --open) REVEAL=1 ;;
        -h|--help) sed -n '3,9p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "Unknown option: $argument" >&2; exit 1 ;;
    esac
done

# --- Build ------------------------------------------------------------------
if [ "$BUILD" -eq 1 ]; then
    if [ "$UNIVERSAL" -eq 1 ]; then
        "$ROOT/Scripts/build_app.sh" --universal
    else
        "$ROOT/Scripts/build_app.sh"
    fi
fi

if [ ! -d "$APP_BUNDLE" ]; then
    echo "error: $APP_BUNDLE not found — run without --no-build" >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_BUNDLE/Contents/Info.plist")"
DMG_PATH="$DIST_DIR/$APP_NAME $VERSION ($BUILD_NUMBER).dmg"

# --- Stage ------------------------------------------------------------------
echo "▸ Staging…"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

# ditto preserves the bundle's symlinks and extended attributes; cp -R does not.
ditto "$APP_BUNDLE" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

# A volume icon, so the mounted disk is not a generic drive.
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$STAGING/.VolumeIcon.icns"
    SetFile -a C "$STAGING" 2>/dev/null || true
fi

# --- Build the image --------------------------------------------------------
echo "▸ Creating the disk image…"
mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    -quiet \
    -ov \
    "$DMG_PATH"

# Fails harmlessly without a signing identity; with one, it makes the image
# tamper-evident.
if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    echo "▸ Signing the image as $CODESIGN_IDENTITY…"
    codesign --force --sign "$CODESIGN_IDENTITY" "$DMG_PATH"
fi

echo "▸ Verifying…"
hdiutil verify "$DMG_PATH" >/dev/null 2>&1 && echo "  image verifies"

SIZE="$(du -h "$DMG_PATH" | cut -f1 | tr -d ' ')"
ARCHS="$(lipo -archs "$APP_BUNDLE/Contents/MacOS/ScreenshotBooster" 2>/dev/null || echo unknown)"
echo "✔ $DMG_PATH"
echo "  $SIZE · $ARCHS · version $VERSION ($BUILD_NUMBER)"

if [ "$REVEAL" -eq 1 ]; then
    open -R "$DMG_PATH"
fi
