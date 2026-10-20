#!/bin/bash
# Package the SwiftPM executable into a double-clickable app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product SonosLocal
BIN="$(swift build -c release --show-bin-path)/SonosLocal"
APP="build/Sonos Local.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SonosLocal"
cp "Sources/SonosApp/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "Sources/SonosApp/Resources/AppIcon.png" ]]; then
  cp "Sources/SonosApp/Resources/AppIcon.png" "$APP/Contents/Resources/AppIcon.png"
fi

# SwiftPM emits a resource bundle next to the executable. Copy it if present.
RES_BUNDLE="$(dirname "$BIN")/SonosLocal_SonosApp.bundle"
if [[ -d "$RES_BUNDLE" ]]; then
  cp -R "$RES_BUNDLE" "$APP/Contents/Resources/"
fi

echo "Built $APP"
