#!/bin/bash
# Package the SwiftPM executable into a double-clickable app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

# Resource-only bundle metadata so codesign accepts a SwiftPM .bundle.
seal_resource_bundle() {
  local bundle="$1"
  local name id plist
  name="$(basename "$bundle" .bundle)"
  id="com.sonoslocal.mac.$(printf '%s' "$name" | tr '_ ' '--' | tr -cd 'A-Za-z0-9.-')"
  plist="$bundle/Info.plist"
  cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>${id}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>${name}</string>
	<key>CFBundlePackageType</key>
	<string>BNDL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>MacOSX</string>
	</array>
	<key>CFBundleVersion</key>
	<string>1</string>
</dict>
</plist>
EOF
}

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
#
# SwiftPM resource bundles are often a bare directory of files. Xcode 26
# codesign rejects those ("bundle format unrecognized"). Give each one a
# resource-only Info.plist, sign it, then sign the app.
if command -v codesign >/dev/null 2>&1; then
  while IFS= read -r -d '' nested; do
    seal_resource_bundle "$nested"
    nested_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$nested/Info.plist")"
    codesign --force --sign - --identifier "$nested_id" "$nested"
  done < <(find "$APP" -name '*.bundle' -print0)
  codesign --force --sign - \
    --identifier com.sonoslocal.mac \
    --entitlements "Sources/SonosApp/SonosLocal.entitlements" \
    "$APP"
  codesign -dv "$APP" 2>&1 | sed -n '1,12p'
fi

echo "Built $APP"
