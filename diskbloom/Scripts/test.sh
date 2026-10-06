#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
plugin="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$plugin" ]]; then
    Scripts/swift.sh test --disable-xctest -Xswiftc -load-plugin-library -Xswiftc "$plugin" "$@"
else
    Scripts/swift.sh test --disable-xctest "$@"
fi
