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
cat > "$TASK_STAGE/Установка.txt" <<'TEXT'
MouseCraft — установка

1. Завершите предыдущую копию MouseCraft через его меню.
2. Перетащите MouseCraft в Applications («Программы»).
3. Извлеките этот диск и запустите MouseCraft из «Программы».
4. В «Обзор» нажмите «Настроить Универсальный доступ» и включите MouseCraft.
   Также разрешите «Мониторинг ввода», если он ещё не выдан.
5. Включите обработку мыши. Статус должен смениться на «Обработка работает».

Текущие настройки не удаляются. После обновления локальной подписи macOS может
потребовать повторно включить разрешение. Это локальная сборка без notarization.
TEXT
hdiutil create -volname "MouseCraft $TASK_VERSION" -srcfolder "$TASK_STAGE" -format UDZO -ov "$TASK_ROOT/dist/$TASK_ASSET.dmg"
hdiutil verify "$TASK_ROOT/dist/$TASK_ASSET.dmg"
mkdir -p "$TASK_ROOT/.build/pkg-scripts"
cat > "$TASK_ROOT/.build/pkg-scripts/preinstall" <<'SCRIPT'
#!/bin/bash
if pgrep -x MouseCraft >/dev/null; then
    echo 'Завершите MouseCraft через его меню и повторите установку.' >&2
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
echo "DMG и PKG готовы в $TASK_ROOT/dist"
