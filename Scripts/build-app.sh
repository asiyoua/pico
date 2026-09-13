#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$ROOT/Pico.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Pico" "$APP/Contents/MacOS/Pico"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon ships as a classic .icns (CFBundleIconFile=AppIcon in Info.plist).
# actool silently drops the AppIcon asset set on this project, so the icon is
# committed as Resources/AppIcon.icns instead of living in the catalog.
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# MIT obligation rides with the distributed copy: keep LICENSE inside the bundle.
cp LICENSE "$APP/Contents/Resources/LICENSE"

# Compile the remaining asset catalog images (menu bar / history icons).
xcrun actool \
  --platform macosx \
  --minimum-deployment-target 15.0 \
  --compile "$APP/Contents/Resources" \
  Resources/Assets.xcassets

ENTITLEMENTS="$ROOT/Resources/Pico.entitlements"
# The signing identity is a hard requirement: exactly "Pico Dev" (stable
# self-signed cert so the macOS accessibility grant survives reinstalls).
# If it is missing, fail loudly instead of signing with anything else — a
# silently different signature would invalidate the TCC grant. Recreate the
# cert per 开发问题与解决方案.md, or override with CODESIGN_IDENTITY=<name>.
IDENTITY="${CODESIGN_IDENTITY:-Pico Dev}"
FOUND="$(security find-identity -p codesigning -v 2>/dev/null || true)"
if ! grep -qF "\"$IDENTITY\"" <<<"$FOUND"; then
  {
    echo "error: codesigning identity \"$IDENTITY\" not found or not valid."
    echo "  Identities currently visible to security:"
    echo "$FOUND" | sed 's/^/    /'
    echo "  If the cert exists but is not listed, add trust:"
    echo "    security add-trusted-cert -p codeSign -k ~/Library/Keychains/login.keychain-db <cert.pem>"
  } >&2
  exit 1
fi
# --timestamp contacts Apple's timestamp server, which is unreachable from
# some networks and hangs the build. The local self-signed identity does
# not need a trusted timestamp: trust anchors on the certificate itself.
if [[ "$IDENTITY" == "Pico Dev" ]]; then
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
echo "Built $APP (signed with $IDENTITY)"
