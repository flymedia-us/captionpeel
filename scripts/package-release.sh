#!/usr/bin/env bash
# Build, sign, notarize, and package CaptionPeel for GitHub Releases.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

OUTPUT_DIR=${OUTPUT_DIR:-"$ROOT/dist"}
SKIP_NOTARIZE=${SKIP_NOTARIZE:-0}
DERIVED=$OUTPUT_DIR/DerivedData
EXPORT_DIR=$OUTPUT_DIR/export
AUTH_KEY_PATH=${APP_STORE_CONNECT_API_KEY_PATH:-}

mkdir -p "$OUTPUT_DIR"

if [[ "$SKIP_NOTARIZE" != "1" ]]; then
  : "${APP_STORE_CONNECT_KEY_ID:?Set APP_STORE_CONNECT_KEY_ID}"
  : "${APP_STORE_CONNECT_ISSUER_ID:?Set APP_STORE_CONNECT_ISSUER_ID}"
  if [[ -z "$AUTH_KEY_PATH" ]]; then
    : "${APP_STORE_CONNECT_API_KEY:?Set APP_STORE_CONNECT_API_KEY or APP_STORE_CONNECT_API_KEY_PATH}"
    AUTH_KEY_PATH=$OUTPUT_DIR/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8
    printf '%s\n' "$APP_STORE_CONNECT_API_KEY" > "$AUTH_KEY_PATH"
    chmod 600 "$AUTH_KEY_PATH"
    trap 'rm -f "$AUTH_KEY_PATH"' EXIT
  fi
fi

echo "==> Building unsigned universal Release"
rm -rf "$DERIVED" "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"
xcodebuild \
  -project CaptionPeel.xcodeproj \
  -scheme CaptionPeel \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  build

APP_SRC=$(find "$DERIVED" -path '*/Build/Products/Release/CaptionPeel.app' -type d | head -n 1)
if [[ -z "$APP_SRC" ]]; then
  echo "error: Release CaptionPeel.app not found under $DERIVED" >&2
  exit 1
fi

APP=$EXPORT_DIR/CaptionPeel.app
ditto "$APP_SRC" "$APP"

if [[ "$SKIP_NOTARIZE" != "1" ]]; then
  echo "==> Signing with Developer ID"
  IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $2; exit}')
  if [[ -z "$IDENTITY" ]]; then
    echo "error: no Developer ID Application identity in the keychain" >&2
    exit 1
  fi
  codesign --force --timestamp --options runtime \
    --entitlements "$ROOT/CaptionPeel/CaptionPeel.entitlements" \
    --generate-entitlement-der \
    --sign "$IDENTITY" \
    "$APP"
  codesign --verify --verbose=2 --strict "$APP"
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG=$OUTPUT_DIR/CaptionPeel-${VERSION}.dmg
APP_ZIP=$OUTPUT_DIR/CaptionPeel-${VERSION}.zip

if [[ "$SKIP_NOTARIZE" != "1" ]]; then
  echo "==> Notarizing app"
  ditto -c -k --keepParent "$APP" "$APP_ZIP"
  xcrun notarytool submit "$APP_ZIP" \
    --key "$AUTH_KEY_PATH" \
    --key-id "$APP_STORE_CONNECT_KEY_ID" \
    --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
    --wait
  xcrun stapler staple "$APP"
fi

"$ROOT/scripts/package-dmg.sh" "$APP" "$DMG"

if [[ "$SKIP_NOTARIZE" != "1" ]]; then
  echo "==> Notarizing DMG"
  xcrun notarytool submit "$DMG" \
    --key "$AUTH_KEY_PATH" \
    --key-id "$APP_STORE_CONNECT_KEY_ID" \
    --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
    --wait
  xcrun stapler staple "$DMG"
fi

echo "version=$VERSION"
echo "dmg=$DMG"
