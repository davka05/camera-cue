#!/bin/bash
set -euo pipefail

source_root="$(cd "$(dirname "$0")/.." && pwd)"
output_directory="${1:-$source_root/dist}"
bundle="$output_directory/Camera Cue.app"
build_directory="$source_root/.build/app"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"

mkdir -p "$build_directory/modules"
xcrun swiftc \
    -O \
    -swift-version 5 \
    -parse-as-library \
    -target "$(uname -m)-apple-macosx14.0" \
    -sdk "$sdk_path" \
    -module-cache-path "$build_directory/modules" \
    "$source_root"/Sources/BelowCamera/*.swift \
    -o "$build_directory/Camera Cue"

mkdir -p "$bundle/Contents/MacOS"
install -m 644 "$source_root/Support/Info.plist" "$bundle/Contents/Info.plist"
install -m 755 "$build_directory/Camera Cue" "$bundle/Contents/MacOS/Camera Cue"
codesign --force --sign - "$bundle"
codesign --verify --strict "$bundle"
printf '%s\n' "$bundle"
