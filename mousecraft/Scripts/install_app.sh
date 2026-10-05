#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_APP="$TASK_ROOT/build/MouseCraft.app"
TASK_DESTINATION="${MOUSECRAFT_INSTALL_DIR:-/Applications}"
case "${1:-}" in
    --no-build) ;;
    '') "$TASK_ROOT/Scripts/build_app.sh" ;;
    *) echo 'Usage: install_app.sh [--no-build]' >&2; exit 1 ;;
esac
test -d "$TASK_APP"
codesign --verify --deep --strict "$TASK_APP"
mkdir -p "$TASK_DESTINATION"
if [ ! -w "$TASK_DESTINATION" ]; then
    echo "Cannot write to $TASK_DESTINATION. Use the DMG or PKG installer; macOS handles administrator authentication." >&2
    exit 1
fi
if pgrep -x MouseCraft >/dev/null; then
    echo 'Quit MouseCraft using its menu before installing.' >&2
    exit 1
fi
# Keep a complete copy of the old installation until the replacement is verified.
TASK_STAGING="$(mktemp -d "$TASK_DESTINATION/.mousecraft-install.XXXXXX")"
trap 'rm -rf "$TASK_STAGING"' EXIT
ditto "$TASK_APP" "$TASK_STAGING/MouseCraft.app"
codesign --verify --deep --strict "$TASK_STAGING/MouseCraft.app"
if [ -e "$TASK_DESTINATION/MouseCraft.app" ]; then
    mkdir -p "$HOME/Library/Application Support/MouseCraft"
    TASK_BACKUP_DIR="$(mktemp -d "$HOME/Library/Application Support/MouseCraft/PreviousInstall.XXXXXX")"
    mv "$TASK_DESTINATION/MouseCraft.app" "$TASK_BACKUP_DIR/MouseCraft.app"
fi
if ! mv "$TASK_STAGING/MouseCraft.app" "$TASK_DESTINATION/MouseCraft.app"; then
    if [ -n "${TASK_BACKUP_DIR:-}" ]; then mv "$TASK_BACKUP_DIR/MouseCraft.app" "$TASK_DESTINATION/MouseCraft.app"; fi
    exit 1
fi
echo "Installed: $TASK_DESTINATION/MouseCraft.app"
echo 'Your settings are retained. Launch this copy and grant permissions to it.'
