#!/bin/bash
# Package the SwiftPM executable into a double-clickable app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

# SwiftPM resource bundles are a flat directory (payload files next to
# Info.plist). macOS 26 codesign --strict rejects that with
# "unsealed contents present in the bundle root". A versioned bundle keeps
# the payload in Contents/Resources and Info.plist in Contents/, which both
# current codesign and Bundle.url(forResource:) accept.
seal_resource_bundle() {
  local bundle="$1"
  [[ -d "$bundle" ]] || return 0
  local name id parent staging entry base
  name="$(basename "$bundle" .bundle)"
  id="com.sonoslocal.mac.$(printf '%s' "$name" | tr '_ ' '--' | tr -cd 'A-Za-z0-9.-')"
  parent="$(dirname "$bundle")"
  staging="$(mktemp -d "${parent}/.seal.XXXXXX")"
  mkdir -p "$staging/Contents/Resources"
  # Snapshot first. Moving entries while find is still walking the directory
  # drops files on some systems.
  local listing
  listing="$(mktemp)"
  find "$bundle" -mindepth 1 -maxdepth 1 -print0 > "$listing"

  while IFS= read -r -d '' entry; do
    base="$(basename "$entry")"
    case "$base" in
      .DS_Store|__MACOSX)
        rm -rf "$entry"
        ;;
      Info.plist|PkgInfo|_CodeSignature)
        ;;
      Contents)
        if [[ -d "$entry/Resources" ]]; then
          cp -R "$entry/Resources/." "$staging/Contents/Resources/"
        fi
        ;;
      *)
        mv "$entry" "$staging/Contents/Resources/$base"
        ;;
    esac
  done < "$listing"
  rm -f "$listing"

  cat > "$staging/Contents/Info.plist" <<EOF
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

  rm -rf "$bundle"
  mv "$staging" "$bundle"

  if [[ ! -f "$bundle/Contents/Info.plist" || ! -d "$bundle/Contents/Resources" ]]; then
    echo "Resource bundle $bundle is missing Contents/Info.plist or Contents/Resources" >&2
    exit 1
  fi
  while IFS= read -r -d '' entry; do
    base="$(basename "$entry")"
    if [[ "$base" != "Contents" ]]; then
      echo "Unsealed item at the root of $bundle: $base" >&2
      exit 1
    fi
  done < <(find "$bundle" -mindepth 1 -maxdepth 1 -print0)
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
# name this tools version produced, then repack each one before signing.
shopt -s nullglob
for bundle in "$(dirname "$BIN")"/*.bundle; do
  cp -R "$bundle" "$APP/Contents/Resources/"
done

# Ad-hoc sign the bundle with the same identifier as CFBundleIdentifier.
# Local Network permission is stored against that identifier; signing the bare
# executable as "SonosLocal" makes every rebuild look like a different app.
if command -v codesign >/dev/null 2>&1; then
  # Collect paths before rewriting them. macOS /bin/bash is 3.2, so avoid
  # expanding an empty array under `set -u`.
  bundle_list="$(mktemp)"
  find "$APP" -name '*.bundle' -print0 > "$bundle_list"
  while IFS= read -r -d '' path; do
    [[ -n "$path" ]] || continue
    seal_resource_bundle "$path"
    nested_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$path/Contents/Info.plist")"
    codesign --force --sign - --identifier "$nested_id" "$path"
  done < "$bundle_list"
  rm -f "$bundle_list"
  sign_args=(--force --sign - --identifier com.sonoslocal.mac --entitlements "Sources/SonosApp/SonosLocal.entitlements")
  help="$(codesign --help 2>&1 || true)"
  if printf '%s\n' "$help" | grep -q -- '--generate-entitlement-der'; then
    sign_args+=(--generate-entitlement-der)
  fi
  codesign "${sign_args[@]}" "$APP"
  codesign --verify --deep --strict "$APP"
  details="$(codesign -dv "$APP" 2>&1)"
  printf '%s\n' "$details" | sed -n '1,12p'
  identifier="$(printf '%s\n' "$details" | sed -n 's/^Identifier=//p' | head -n 1)"
  if [[ "$identifier" != "com.sonoslocal.mac" ]]; then
    echo "codesign identifier is '${identifier:-missing}', expected com.sonoslocal.mac" >&2
    exit 1
  fi
fi

echo "Built $APP"
