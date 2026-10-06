#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="1.75.1"
architecture="$(uname -m)"
case "$architecture" in arm64) arch="arm64" ;; x86_64) arch="amd64" ;; *) exit 1 ;; esac
destination="$PWD/.build/vendor/rclone-$version-$arch"
if [[ -x "$destination/rclone" ]]; then exit 0; fi
mkdir -p "$destination"
archive="rclone-v$version-osx-$arch.zip"
curl --fail --location --silent --show-error "https://downloads.rclone.org/v$version/$archive" -o "$destination/$archive"
curl --fail --location --silent --show-error "https://downloads.rclone.org/v$version/SHA256SUMS" -o "$destination/SHA256SUMS"
expected="$(awk -v archive="$archive" '$2 == archive || $2 == "*" archive {print $1}' "$destination/SHA256SUMS")"
actual="$(shasum -a 256 "$destination/$archive" | awk '{print $1}')"
if [[ -z "$expected" || "$actual" != "$expected" ]]; then
    echo "rclone checksum verification failed" >&2
    exit 1
fi
unzip -p "$destination/$archive" "rclone-v$version-osx-$arch/rclone" > "$destination/rclone"
unzip -p "$destination/$archive" "rclone-v$version-osx-$arch/README.txt" > "$destination/README.txt"
chmod 755 "$destination/rclone"
echo "Verified rclone $version ($arch)"
