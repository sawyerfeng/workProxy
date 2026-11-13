#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test -z "$(git status --porcelain --untracked-files=no)" || { echo 'Commit tracked changes before packaging a release.' >&2; exit 1; }
./scripts/build-app.sh
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
release_dir="$PWD/dist/release/$version"
tools_dir="$PWD/.build/artifacts/sparkle/Sparkle/bin"
account='io.github.sawyerfeng.workproxy'
expected_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Resources/Info.plist)"
test "$expected_key" = "$("$tools_dir/generate_keys" --account "$account" -p)" || { echo 'The Sparkle signing key does not match Info.plist.' >&2; exit 1; }
test ! -e "$release_dir" || { echo "Release directory already exists: $release_dir" >&2; exit 1; }
mkdir -p "$release_dir"
archive="workProxy-$version-macos-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent dist/workProxy.app "$release_dir/$archive"
awk -v header="## $version - " 'index($0,header)==1 { found=1; next } found && /^## / { exit } found { print }' CHANGELOG.zh.md > "$release_dir/${archive%.zip}.md"
test -s "$release_dir/${archive%.zip}.md"
"$tools_dir/generate_appcast" --account "$account" --embed-release-notes \
    --download-url-prefix "https://github.com/sawyerfeng/workProxy/releases/download/v$version/" \
    --link 'https://github.com/sawyerfeng/workProxy' "$release_dir"
"$tools_dir/sign_update" --verify --account "$account" "$release_dir/appcast.xml"
signature="$(/usr/bin/xmllint --xpath 'string(//*[local-name()="enclosure"]/@*[local-name()="edSignature"])' "$release_dir/appcast.xml")"
"$tools_dir/sign_update" --verify --account "$account" "$release_dir/$archive" "$signature"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
ditto dist/workProxy.app "$stage/workProxy.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "workProxy $version" -srcfolder "$stage" -ov -format UDZO "$release_dir/workProxy-$version-macos-arm64.dmg"
hdiutil verify "$release_dir/workProxy-$version-macos-arm64.dmg"
git archive --format=zip --prefix="workProxy-$version/" HEAD > "$release_dir/workProxy-$version-source.zip"
cd "$release_dir"
shasum -a 256 "$archive" "workProxy-$version-macos-arm64.dmg" "workProxy-$version-source.zip" appcast.xml > SHA256SUMS.txt
shasum -a 256 -c SHA256SUMS.txt
printf 'Release artifacts: %s\n' "$release_dir"
