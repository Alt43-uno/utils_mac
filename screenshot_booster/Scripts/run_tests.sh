#!/bin/bash
#
# Builds and runs the project's checks.
#
#   ./Scripts/run_tests.sh
#   ./Scripts/run_tests.sh --rendering-only   no screenshot library writes
#
# The suites live in Tests/ and are compiled together with the app's sources.
# Storage checks use a temporary directory compiled into the test executable.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DEPLOYMENT_TARGET="26.0"
BINARY="$ROOT/.build/tests/ScreenshotBoosterTests"

echo "▸ Building the tests…"
mkdir -p "$(dirname "$BINARY")"

# Every source except the app's entry point, plus the suites.
SOURCES=()
while IFS= read -r -d '' source; do
    SOURCES+=("$source")
done < <(find "$ROOT/Sources" -name '*.swift' ! -name 'main.swift' -print0)
while IFS= read -r -d '' source; do
    SOURCES+=("$source")
done < <(find "$ROOT/Tests" -name '*.swift' -print0)

xcrun swiftc \
    -D SCREENSHOT_BOOSTER_TESTS \
    -swift-version 5 \
    -target "$(uname -m)-apple-macos${DEPLOYMENT_TARGET}" \
    -sdk "$(xcrun --show-sdk-path)" \
    -o "$BINARY" \
    "${SOURCES[@]}"

echo "▸ Running…"
"$BINARY" "$@"
