#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
xcodebuild -project Lumen.xcodeproj -scheme Lumen -configuration Release \
  -derivedDataPath .build CODE_SIGNING_ALLOWED=NO build
APP="$PWD/.build/Build/Products/Release/Lumen.app"
# Local ad-hoc signing; no Apple account or paid developer membership required.
codesign --force --sign - "$APP"
printf '\nBuilt: %s\nOpen with: open "%s"\n' "$APP" "$APP"
