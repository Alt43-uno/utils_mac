#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"
case "${1:-}" in
    --no-build) ;;
    '') ./Scripts/build_app.sh ;;
    *) echo 'Usage: make_installer.sh [--no-build]' >&2; exit 1 ;;
esac
TASK_APP="$TASK_ROOT/build/MouseCraft.app"
TASK_VERSION="$(plutil -extract CFBundleShortVersionString raw "$TASK_APP/Contents/Info.plist")"
TASK_ARCHS="$(lipo -archs "$TASK_APP/Contents/MacOS/MouseCraft")"
if [[ " $TASK_ARCHS " == *" arm64 "* && " $TASK_ARCHS " == *" x86_64 "* ]]; then
    TASK_SUFFIX=universal
else
    TASK_SUFFIX="$TASK_ARCHS"
fi
TASK_ASSET="MouseCraft-$TASK_VERSION-$TASK_SUFFIX"
codesign --verify --deep --strict "$TASK_APP"
mkdir -p "$TASK_ROOT/dist"
TASK_STAGE="$(mktemp -d "$TASK_ROOT/build/installer.XXXXXX")"
trap 'rm -rf "$TASK_STAGE"' EXIT
ditto "$TASK_APP" "$TASK_STAGE/MouseCraft.app"
ln -s /Applications "$TASK_STAGE/Applications"
cat > "$TASK_STAGE/Installation.txt" <<'TEXT'
MouseCraft — Installation

1. Quit any previous copy of MouseCraft using its menu.
2. Drag MouseCraft into Applications.
3. Eject this disk and open MouseCraft from Applications.
4. In Overview, click Set Up Accessibility and enable MouseCraft in System Settings.
   Also grant Input Monitoring if it is not already enabled.
5. Enable MouseCraft. Its status should say "Processing is active".

Your existing settings are retained. After an update, macOS may require you to
re-enable permissions. This build is signed ad hoc and is not notarized.
TEXT
hdiutil create -volname "MouseCraft $TASK_VERSION" -srcfolder "$TASK_STAGE" -format UDZO -ov "$TASK_ROOT/dist/$TASK_ASSET.dmg"
hdiutil verify "$TASK_ROOT/dist/$TASK_ASSET.dmg"
mkdir -p "$TASK_ROOT/.build/pkg-scripts"
cat > "$TASK_ROOT/.build/pkg-scripts/preinstall" <<'SCRIPT'
#!/bin/bash
if pgrep -x MouseCraft >/dev/null; then
    echo 'Quit MouseCraft using its menu and try installing again.' >&2
    exit 1
fi
exit 0
SCRIPT
chmod +x "$TASK_ROOT/.build/pkg-scripts/preinstall"
TASK_PAYLOAD="$(mktemp -d "$TASK_ROOT/build/pkg-payload.XXXXXX")"
trap 'rm -rf "$TASK_STAGE" "$TASK_PAYLOAD"' EXIT
ditto "$TASK_APP" "$TASK_PAYLOAD/MouseCraft.app"
pkgbuild --analyze --root "$TASK_PAYLOAD" "$TASK_PAYLOAD/components.plist"
# Always install in /Applications, even if a development copy is registered.
/usr/libexec/PlistBuddy -c 'Set :0:BundleIsRelocatable false' "$TASK_PAYLOAD/components.plist"
mv "$TASK_PAYLOAD/components.plist" "$TASK_ROOT/.build/pkg-components.plist"
pkgbuild --root "$TASK_PAYLOAD" --component-plist "$TASK_ROOT/.build/pkg-components.plist" --install-location /Applications \
    --identifier app.mousecraft.installer --version "$TASK_VERSION" \
    --scripts "$TASK_ROOT/.build/pkg-scripts" "$TASK_ROOT/dist/$TASK_ASSET.pkg"
(cd "$TASK_ROOT/dist" && shasum -a 256 "$TASK_ASSET.dmg" "$TASK_ASSET.pkg" > "$TASK_ASSET.sha256")
echo "DMG and PKG installers are ready in $TASK_ROOT/dist"
