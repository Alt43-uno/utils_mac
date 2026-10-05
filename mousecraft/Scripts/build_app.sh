#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"
source "$TASK_ROOT/Scripts/toolchain_env.sh"
CONFIGURATION=release
TASK_UNIVERSAL=0
for TASK_OPTION in "$@"; do
    case "$TASK_OPTION" in
        --debug) CONFIGURATION=debug ;;
        --universal) TASK_UNIVERSAL=1 ;;
        *) echo 'Usage: build_app.sh [--debug] [--universal]' >&2; exit 1 ;;
    esac
done
TASK_BUILD_FLAGS=(-c "$CONFIGURATION" --sdk "$TASK_SDK")
if [ "$TASK_UNIVERSAL" -eq 1 ]; then TASK_BUILD_FLAGS+=(--arch arm64 --arch x86_64); fi
swift build "${TASK_BUILD_FLAGS[@]}"
BIN_DIR="$(swift build "${TASK_BUILD_FLAGS[@]}" --show-bin-path)"
APP="$TASK_ROOT/build/MouseCraft.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MouseCraft" "$APP/Contents/MacOS/MouseCraft"
if [ "$TASK_UNIVERSAL" -eq 1 ]; then
    for TASK_ARCH in arm64 x86_64; do lipo "$APP/Contents/MacOS/MouseCraft" -verify_arch "$TASK_ARCH"; done
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
TASK_ICONSET="$TASK_ROOT/.build/AppIcon.iconset"
mkdir -p "$TASK_ICONSET"
xcrun swift -sdk "$TASK_SDK" Scripts/make_icon.swift "$TASK_ROOT/.build/icon.png"
for TASK_ICON_SIZE in 16 32 128 256 512; do
    sips -z "$TASK_ICON_SIZE" "$TASK_ICON_SIZE" "$TASK_ROOT/.build/icon.png" --out "$TASK_ICONSET/icon_${TASK_ICON_SIZE}x${TASK_ICON_SIZE}.png" >/dev/null
    sips -z "$((TASK_ICON_SIZE * 2))" "$((TASK_ICON_SIZE * 2))" "$TASK_ROOT/.build/icon.png" --out "$TASK_ICONSET/icon_${TASK_ICON_SIZE}x${TASK_ICON_SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$TASK_ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp "$TASK_ROOT/../LICENSE" "$APP/Contents/Resources/LICENSE"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --sign "${CODESIGN_IDENTITY:--}" --identifier app.mousecraft.desktop --timestamp=none "$APP"
codesign --verify --deep --strict --all-architectures "$APP"
echo "Built: $APP"
