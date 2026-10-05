#!/bin/bash
# Sourced by build/test scripts. Work around mismatched CLT private interfaces
# in a LOCAL copy only; do not alter the installed toolchain.
TASK_TOOLCHAIN="$(xcode-select -p)"
TASK_SWIFT_USR="$(cd "$(dirname "$(xcrun --find swift)")/.." && pwd)"
TASK_PM_LIBS="$TASK_SWIFT_USR/lib/swift/pm"
TASK_MANIFEST_INTERFACE="$TASK_PM_LIBS/ManifestAPI/PackageDescription.swiftmodule/$(uname -m)-apple-macos"
if [ -f "$TASK_MANIFEST_INTERFACE.private.swiftinterface" ] &&
   ! grep -q 'swiftLanguageModes' "$TASK_MANIFEST_INTERFACE.private.swiftinterface" &&
   grep -q 'swiftLanguageModes' "$TASK_MANIFEST_INTERFACE.swiftinterface"; then
    TASK_LOCAL_PM="$TASK_ROOT/.build/swiftpm-libs"
    mkdir -p "$TASK_LOCAL_PM/ManifestAPI/PackageDescription.swiftmodule"
    cp "$TASK_PM_LIBS/ManifestAPI/libPackageDescription.dylib" "$TASK_LOCAL_PM/ManifestAPI/"
    for TASK_INTERFACE in "$TASK_PM_LIBS/ManifestAPI/PackageDescription.swiftmodule/"*.swiftinterface; do
        case "$TASK_INTERFACE" in *.private.swiftinterface) continue ;; esac
        cp "$TASK_INTERFACE" "$TASK_LOCAL_PM/ManifestAPI/PackageDescription.swiftmodule/"
    done
    export SWIFTPM_CUSTOM_LIBS_DIR="$TASK_LOCAL_PM"
fi
TASK_SDK="${MOUSECRAFT_SDK:-$(xcrun --show-sdk-path)}"
# A beta SDK may require SwiftUI macro plugins not shipped in CLT.
if [ -z "${MOUSECRAFT_SDK:-}" ] && [ "$(xcrun --show-sdk-version)" = "27.0" ] &&
   [ -d "$TASK_TOOLCHAIN/SDKs/MacOSX26.5.sdk" ]; then
    TASK_SDK="$TASK_TOOLCHAIN/SDKs/MacOSX26.5.sdk"
fi
