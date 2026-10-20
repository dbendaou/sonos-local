#!/bin/bash
# Package the SwiftPM executable into a double-clickable app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

# Command Line Tools can build this. The deployment target stays 14 so the
# binary runs on macOS 14 and later, including macOS 26.
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"
# shellcheck source=select-sdk.sh
source "$(cd "$(dirname "$0")" && pwd)/select-sdk.sh"
select_macos_sdk

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

# Ad-hoc sign the bundle with the same identifier as CFBundleIdentifier.
# Local Network permission is stored against that identifier; signing the bare
# executable as "SonosLocal" makes every rebuild look like a different app.
if command -v codesign >/dev/null 2>&1; then
  while IFS= read -r -d '' nested; do
    codesign --force --sign - "$nested"
  done < <(find "$APP" -name '*.bundle' -print0)
  codesign --force --sign - \
    --identifier com.sonoslocal.mac \
    --entitlements "Sources/SonosApp/SonosLocal.entitlements" \
    "$APP"
  codesign -dv "$APP" 2>&1 | sed -n '1,12p'
fi

echo "Built $APP"
