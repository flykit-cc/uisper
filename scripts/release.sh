#!/usr/bin/env bash
# Build a Release .app, zip it, and publish a GitHub release. Usage: scripts/release.sh 0.1.0
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?version, e.g. 0.1.0}"
xcodegen generate --quiet
xcodebuild -project Uisper.xcodeproj -scheme Uisper -configuration Release -derivedDataPath build \
  MARKETING_VERSION="$VERSION" build 2>&1 | grep -E "error:|BUILD" || status=${PIPESTATUS[0]}
(( ${status:-0} == 0 )) || { echo "build failed"; exit "$status"; }
APP="build/Build/Products/Release/uisper.app"
codesign --force --deep --sign - "$APP"          # ad-hoc: runs anywhere after right-click > Open
ZIP="build/uisper-$VERSION.zip"
rm -f "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"
echo "zip: $ZIP ($(du -h "$ZIP" | cut -f1))"
gh release create "v$VERSION" "$ZIP" --title "uisper $VERSION" --notes-file - <<NOTES
Native, fully local dictation for macOS 26 on Apple silicon.

**Install:** unzip, move uisper.app to Applications, then **right-click > Open** once (the build is not notarized). Grant Microphone, Accessibility and Input Monitoring when asked, then relaunch.

Turn on Apple Intelligence in System Settings for the grammar cleanup step.
NOTES
