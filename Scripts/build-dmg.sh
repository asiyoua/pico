#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "create-dmg is required. Install with: brew install create-dmg" >&2
  exit 1
fi

zsh "$ROOT/Scripts/build-app.sh"

APP="$ROOT/Pico.app"
STAGE="$ROOT/dist/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/Pico.app"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$ROOT/dist/Pico-${VERSION}.dmg"

create-dmg \
  --volname "Pico" \
  --volicon "$APP/Contents/Resources/AppIcon.icns" \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "Pico.app" 150 200 \
  --hide-extension "Pico.app" \
  --app-drop-link 450 200 \
  --overwrite \
  "$DMG" \
  "$STAGE/"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  echo "Notarized and stapled $DMG"
else
  echo "Built $DMG (not notarized; set NOTARY_PROFILE to notarize)"
fi
