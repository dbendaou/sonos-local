#!/bin/bash
# Package the SwiftPM executable into a double-clickable app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

# Command Line Tools can build this. The deployment target stays 14 so the
# binary runs on macOS 14 and later, including macOS 26.
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"

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

# SwiftPM emits a resource bundle next to the executable. Copy whichever
# name this tools version produced.
shopt -s nullglob
for bundle in "$(dirname "$BIN")"/*.bundle; do
  cp -R "$bundle" "$APP/Contents/Resources/"
done

echo "Built $APP"
