#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
swift build --disable-sandbox -c release
bin_path="$(swift build --disable-sandbox -c release --show-bin-path)"
app_path="$PWD/dist/workProxy.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$app_path/Contents/Frameworks"
ditto "$PWD/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$app_path/Contents/Frameworks/Sparkle.framework"
cp "$bin_path/WorkProxy" "$app_path/Contents/MacOS/WorkProxy"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
cp Resources/AppIcon.icns "$app_path/Contents/Resources/AppIcon.icns"
cp Resources/Sparkle-LICENSE.txt "$app_path/Contents/Resources/Sparkle-LICENSE.txt"
codesign --force --sign - "$app_path"
codesign --verify --deep --strict "$app_path"
printf 'Built %s\n' "$app_path"
