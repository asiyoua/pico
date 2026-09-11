#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$ROOT/FloatTrans.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/FloatTrans" "$APP/Contents/MacOS/FloatTrans"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon ships as a classic .icns (CFBundleIconFile=AppIcon in Info.plist).
# actool silently drops the AppIcon asset set on this project, so the icon is
# committed as Resources/AppIcon.icns instead of living in the catalog.
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Compile the remaining asset catalog images (menu bar / history icons).
xcrun actool \
  --platform macosx \
  --minimum-deployment-target 15.0 \
  --compile "$APP/Contents/Resources" \
  Resources/Assets.xcassets

ENTITLEMENTS="$ROOT/Resources/LiveEnglish.entitlements"
# Prefer the stable self-signed identity ("FloatTrans Dev") so the macOS
# accessibility grant survives reinstalls; fall back to ad-hoc. An explicit
# CODESIGN_IDENTITY always wins.
IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]] && security find-identity -p codesigning -v 2>/dev/null | grep -q '"FloatTrans Dev"'; then
  IDENTITY="FloatTrans Dev"
fi
if [[ -n "$IDENTITY" ]]; then
  # --timestamp contacts Apple's timestamp server, which is unreachable from
  # some networks and hangs the build. The local self-signed identity does
  # not need a trusted timestamp: trust anchors on the certificate itself.
  if [[ "$IDENTITY" == "FloatTrans Dev" ]]; then
    codesign --force --options runtime \
      --sign "$IDENTITY" \
      --entitlements "$ENTITLEMENTS" \
      "$APP"
  else
    codesign --force --options runtime --timestamp \
      --sign "$IDENTITY" \
      --entitlements "$ENTITLEMENTS" \
      "$APP"
  fi
  codesign --verify --deep --strict "$APP"
else
  codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP"
fi
echo "Built $APP (signed with ${IDENTITY:-adhoc})"
