#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" == --no-build && $# == 1 ]]; then
    :
elif [[ $# == 0 ]]; then
    Scripts/build_app.sh --cloud
else
    echo "Usage: Scripts/make_release.sh [--no-build]" >&2
    exit 1
fi
app="$PWD/build/DiskBloom.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
architecture="$(lipo -archs "$app/Contents/MacOS/DiskBloom")"
case "$architecture" in arm64|x86_64) ;; *) echo "Expected a single-architecture build" >&2; exit 1 ;; esac
if [[ "$(lipo -archs "$app/Contents/MacOS/DiskBloomWorker")" != "$architecture" ]]; then
    echo "Worker architecture does not match the app" >&2
    exit 1
fi
codesign --verify --deep --strict "$app"
base="DiskBloom-$version-$architecture"
mkdir -p dist
staging="$(mktemp -d "$PWD/.build/release-stage.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/DiskBloom.app"
ln -s /Applications "$staging/Applications"
cat > "$staging/Read Me.txt" <<EOF
DiskBloom $version — Preview ($architecture)

Drag DiskBloom.app into Applications, then launch the installed copy.
Requires macOS 14 or later. This preview is signed ad hoc and not notarized.
If macOS blocks launch, review Apple's guidance for an app you trust:
https://support.apple.com/102445

Choose a disk or folder, scan it, and inspect the radial map. Review files in
the collection before removal. Local removal defaults to Trash; cloud
removal follows the provider's rules and may be permanent.

Full Disk Access is granted manually in System Settings when needed.
This build includes rclone for optional cloud connections.

Known limitations and usage:
https://github.com/Alt43-uno/utils_mac/tree/diskbloom-v$version/diskbloom

Original application code: MIT. Third-party notices are in the app bundle.
EOF
# ditto preserves app permissions, links, and macOS bundle metadata.
ditto -c -k --keepParent "$app" "dist/$base.zip"
image="$PWD/dist/$base.dmg"
if [[ -e "$image" ]]; then rm "$image"; fi
hdiutil create -volname "DiskBloom $version" -srcfolder "$staging" -format UDZO -ov "$image"
hdiutil verify "$image"
(cd dist && shasum -a 256 "$base.dmg" "$base.zip" > "$base.sha256")
echo "Release assets: dist/$base.{dmg,zip,sha256}"
