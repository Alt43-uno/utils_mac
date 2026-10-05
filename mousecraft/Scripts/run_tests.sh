#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"
source "$TASK_ROOT/Scripts/toolchain_env.sh"
TASK_TEST_PLUGINS="$TASK_SWIFT_USR/lib/swift/host/plugins/testing"
if [ -d "$TASK_TEST_PLUGINS" ]; then
    swift test --sdk "$TASK_SDK" --disable-xctest --enable-swift-testing -Xswiftc -plugin-path -Xswiftc "$TASK_TEST_PLUGINS"
else
    swift test --sdk "$TASK_SDK" --disable-xctest --enable-swift-testing
fi
