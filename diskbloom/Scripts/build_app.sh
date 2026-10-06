#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="release"
cloud=false
for argument in "$@"; do
    case "$argument" in
        --cloud) cloud=true ;;
        --debug) configuration="debug" ;;
        *) echo "Usage: Scripts/build_app.sh [--cloud] [--debug]" >&2; exit 1 ;;
    esac
done
Scripts/swift.sh build -c "$configuration"
bin="$(Scripts/swift.sh build -c "$configuration" --show-bin-path)"
app="$PWD/build/DiskBloom.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/DiskBloom" "$app/Contents/MacOS/DiskBloom.new"
mv "$app/Contents/MacOS/DiskBloom.new" "$app/Contents/MacOS/DiskBloom"
cp "$bin/DiskBloomWorker" "$app/Contents/MacOS/DiskBloomWorker.new"
mv "$app/Contents/MacOS/DiskBloomWorker.new" "$app/Contents/MacOS/DiskBloomWorker"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp ../LICENSE "$app/Contents/Resources/LICENSE.txt"
cp Resources/PrivacyInfo.xcprivacy Resources/ThirdPartyNotices.txt "$app/Contents/Resources/"
if [[ ! -f Resources/AppIcon.icns ]]; then
    xcrun swift Scripts/make_icon.swift "$PWD/.build/AppIcon.iconset"
    iconutil -c icns .build/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$app/Contents/Resources/"
if [[ "$cloud" == true ]]; then
    Scripts/fetch-rclone.sh
    architecture="$(uname -m)"
    if [[ "$architecture" == x86_64 ]]; then architecture="amd64"; fi
    cp ".build/vendor/rclone-1.75.1-$architecture/rclone" "$app/Contents/Resources/rclone.new"
    mv "$app/Contents/Resources/rclone.new" "$app/Contents/Resources/rclone"
    codesign --force --sign - "$app/Contents/Resources/rclone"
else
    if [[ -f "$app/Contents/Resources/rclone" ]]; then rm "$app/Contents/Resources/rclone"; fi
fi
codesign --force --sign - "$app/Contents/MacOS/DiskBloomWorker"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
ditto -c -k --keepParent "$app" build/DiskBloom.zip
echo "$app"
