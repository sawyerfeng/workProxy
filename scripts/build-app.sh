#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
swift build --disable-sandbox -c release
bin_path="$(swift build --disable-sandbox -c release --show-bin-path)"
app_path="$PWD/dist/workProxy.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_path/WorkProxy" "$app_path/Contents/MacOS/WorkProxy"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
cp Resources/AppIcon.icns "$app_path/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app_path"
printf 'Built %s\n' "$app_path"
