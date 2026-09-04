#!/usr/bin/env bash
# Build uisper.app with the local signing identity and open it.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild -project Uisper.xcodeproj -scheme Uisper -configuration Debug \
  -derivedDataPath build build 2>&1 | grep -E "error:|warning: .*Uisper|BUILD" || true
APP="build/Build/Products/Debug/uisper.app"
test -d "$APP" || { echo "build failed"; exit 1; }
codesign --verify --deep --strict "$APP" && echo "signed ok: $APP"
if [[ "${1:-}" == "--open" ]]; then open "$APP"; fi
