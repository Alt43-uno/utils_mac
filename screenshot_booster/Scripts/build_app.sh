#!/bin/bash
#
# Builds Screenshot Booster.app.
#
#   ./Scripts/build_app.sh              release build for this Mac's architecture
#   ./Scripts/build_app.sh --debug      unoptimised build with debug info
#   ./Scripts/build_app.sh --universal  arm64 + x86_64 fat binary
#   ./Scripts/build_app.sh --install    replace /Applications/Screenshot Booster.app
#   ./Scripts/build_app.sh --run        launch the app when the build finishes
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Screenshot Booster"
EXECUTABLE="ScreenshotBooster"
BUNDLE_ID="com.screenshotbooster.app"
DEPLOYMENT_TARGET="26.0"

BUILD_DIR="$ROOT/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONFIGURATION="release"
UNIVERSAL=0
RUN_AFTER_BUILD=0
INSTALL=0

for argument in "$@"; do
    case "$argument" in
        --debug) CONFIGURATION="debug" ;;
        --release) CONFIGURATION="release" ;;
        --universal) UNIVERSAL=1 ;;
        --run) RUN_AFTER_BUILD=1 ;;
        --install) INSTALL=1 ;;
        -h|--help) sed -n '3,11p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "Unknown option: $argument" >&2; exit 1 ;;
    esac
done

if ! command -v xcrun >/dev/null 2>&1; then
    echo "error: Xcode command line tools are required (xcode-select --install)" >&2
    exit 1
fi

SDK_PATH="$(xcrun --show-sdk-path)"
SOURCES=$(find "$ROOT/Sources" -name '*.swift' | sort)

COMMON_FLAGS=(-swift-version 5 -sdk "$SDK_PATH")
if [ "$CONFIGURATION" = "release" ]; then
    COMMON_FLAGS+=(-O -wmo)
else
    COMMON_FLAGS+=(-Onone -g)
fi

echo "▸ Building ($CONFIGURATION)…"
rm -rf "$APP_BUNDLE"
mkdir -p "$BUILD_DIR/obj"

compile_slice() {
    local arch="$1"
    local output="$2"
    xcrun swiftc "${COMMON_FLAGS[@]}" \
        -target "${arch}-apple-macos${DEPLOYMENT_TARGET}" \
        -o "$output" \
        $SOURCES
}

if [ "$UNIVERSAL" -eq 1 ]; then
    compile_slice arm64 "$BUILD_DIR/obj/$EXECUTABLE-arm64"
    compile_slice x86_64 "$BUILD_DIR/obj/$EXECUTABLE-x86_64"
    xcrun lipo -create \
        "$BUILD_DIR/obj/$EXECUTABLE-arm64" \
        "$BUILD_DIR/obj/$EXECUTABLE-x86_64" \
        -output "$BUILD_DIR/obj/$EXECUTABLE"
else
    compile_slice "$(uname -m)" "$BUILD_DIR/obj/$EXECUTABLE"
fi

echo "▸ Assembling the bundle…"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/obj/$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE"
cp "$ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

# --- Icon -------------------------------------------------------------------
ICNS="$ROOT/Resources/AppIcon.icns"
if [ ! -f "$ICNS" ]; then
    echo "▸ Rendering the app icon…"
    ICON_WORK="$BUILD_DIR/icon"
    rm -rf "$ICON_WORK"
    mkdir -p "$ICON_WORK/AppIcon.iconset"
    xcrun swift "$ROOT/Scripts/make_icon.swift" "$ICON_WORK/icon-1024.png" >/dev/null
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$ICON_WORK/icon-1024.png" \
            --out "$ICON_WORK/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
        sips -z $((size * 2)) $((size * 2)) "$ICON_WORK/icon-1024.png" \
            --out "$ICON_WORK/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICON_WORK/AppIcon.iconset" -o "$ICNS"
fi
cp "$ICNS" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# --- Signing ----------------------------------------------------------------
# Screen Recording permission is tied to the code signature. An ad-hoc signature
# changes on every build, so macOS re-asks each time; set CODESIGN_IDENTITY to a
# real certificate ("Apple Development: …") to keep the grant stable.
IDENTITY="${CODESIGN_IDENTITY:--}"
if [ "$IDENTITY" = "-" ]; then
    echo "▸ Signing (ad-hoc)…"
else
    echo "▸ Signing as $IDENTITY…"
fi
codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none "$APP_BUNDLE" >/dev/null 2>&1 || {
    echo "warning: signing failed; the app will still run but macOS may re-ask for permissions" >&2
}
if [ "$IDENTITY" = "-" ]; then
    echo "  note: re-grant Screen Recording after this build if captures come back empty"
fi

# Refresh Launch Services so the icon and Login Item registration pick up the
# new build instead of a stale copy.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$APP_BUNDLE" >/dev/null 2>&1 || true

echo "✔ Built $APP_BUNDLE"

# --- Install ----------------------------------------------------------------
# Running two copies with the same bundle id from different paths gives each its
# own Screen Recording grant, which reads as "it keeps asking me". Installing
# replaces the one in /Applications and launches from there.
LAUNCH_TARGET="$APP_BUNDLE"
if [ "$INSTALL" -eq 1 ]; then
    echo "▸ Installing to /Applications…"
    pkill -x "$EXECUTABLE" >/dev/null 2>&1 || true
    sleep 1
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_BUNDLE" /Applications/
    xattr -d -r com.apple.quarantine "/Applications/$APP_NAME.app" 2>/dev/null || true
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -f "/Applications/$APP_NAME.app" >/dev/null 2>&1 || true
    LAUNCH_TARGET="/Applications/$APP_NAME.app"
    echo "✔ Installed $LAUNCH_TARGET"
fi

if [ "$RUN_AFTER_BUILD" -eq 1 ]; then
    echo "▸ Launching…"
    pkill -x "$EXECUTABLE" >/dev/null 2>&1 || true
    open "$LAUNCH_TARGET"
fi
