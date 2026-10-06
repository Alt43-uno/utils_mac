#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Use native SwiftPM for the test runner. App release builds use SwiftBuild.
options=(--build-system native --disable-xctest --enable-swift-testing)
developer="$(xcode-select -p)"
for frameworks in "$developer/Library/Developer/Frameworks" \
                  "$developer/Platforms/MacOSX.platform/Developer/Library/Frameworks"; do
    if [[ -d "$frameworks/Testing.framework" ]]; then
        # New CLT layouts package Swift Testing as a developer framework.
        options+=(-Xswiftc -F -Xswiftc "$frameworks" -Xlinker -rpath -Xlinker "$frameworks")
        export DYLD_FRAMEWORK_PATH="$frameworks${DYLD_FRAMEWORK_PATH:+:$DYLD_FRAMEWORK_PATH}"
        break
    fi
done
plugin="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$plugin" ]]; then
    options+=(-Xswiftc -load-plugin-library -Xswiftc "$plugin")
fi
Scripts/swift.sh test "${options[@]}" "$@"
