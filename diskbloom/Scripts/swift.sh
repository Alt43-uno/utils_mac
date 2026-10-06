#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
compiler="$(xcrun --find swift)"
manifest_api="$(dirname "$compiler")/../lib/swift/pm/ManifestAPI"
public_interface="$manifest_api/PackageDescription.swiftmodule/arm64-apple-macos.swiftinterface"
private_interface="$manifest_api/PackageDescription.swiftmodule/arm64-apple-macos.private.swiftinterface"
# Some preview Command Line Tools ship a stale private PackageDescription
# interface. Repair only a local copy; never alter the installed toolchain.
if [[ -f "$public_interface" && -f "$private_interface" ]] &&
   /usr/bin/grep -q 'final public var swiftLanguageModes' "$public_interface" &&
   ! /usr/bin/grep -q 'final public var swiftLanguageModes' "$private_interface"; then
    mkdir -p .build/toolchain
    if [[ ! -f .build/toolchain/ManifestAPI/.diskbloom-overlay ]]; then
        cp -R "$manifest_api" .build/toolchain/
        for architecture in arm64 x86_64; do
            interface=".build/toolchain/ManifestAPI/PackageDescription.swiftmodule/$architecture-apple-macos.swiftinterface"
            if [[ -f "$interface" ]]; then
                cp "$interface" "${interface%.swiftinterface}.private.swiftinterface"
            fi
        done
        touch .build/toolchain/ManifestAPI/.diskbloom-overlay
    fi
    export SWIFTPM_CUSTOM_LIBS_DIR="$PWD/.build/toolchain"
fi
stable_sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
case "${1:-}" in
    build|test|run)
        if [[ -d "$stable_sdk" && "$*" != *--sdk* ]]; then
            exec "$compiler" "$@" --sdk "$stable_sdk"
        fi
        ;;
esac
exec "$compiler" "$@"
