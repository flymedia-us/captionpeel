#!/usr/bin/env bash
# Build a drag-to-Applications DMG from an already-built CaptionPeel.app.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <CaptionPeel.app> <output.dmg>" >&2
  exit 2
fi

APP_SRC=$1
DMG_OUT=$2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BACKGROUND=$ROOT/packaging/dmg/background@2x.png
SETTINGS=$ROOT/packaging/dmg/settings.py
REQUIREMENTS=$ROOT/packaging/dmg/requirements.txt

if [[ ! -d "$APP_SRC" ]]; then
  echo "error: app bundle not found: $APP_SRC" >&2
  exit 1
fi
if [[ ! -f "$BACKGROUND" || ! -f "$SETTINGS" ]]; then
  echo "error: missing DMG packaging assets" >&2
  exit 1
fi

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/captionpeel-dmg.XXXXXX")
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

mkdir -p "$STAGE/source"
cp -R "$APP_SRC" "$STAGE/source/CaptionPeel.app"

echo "==> Installing dmgbuild in an ephemeral environment"
python3 -m venv "$STAGE/venv"
"$STAGE/venv/bin/pip" install --quiet --disable-pip-version-check -r "$REQUIREMENTS"

mkdir -p "$(dirname "$DMG_OUT")"
rm -f "$DMG_OUT"
"$STAGE/venv/bin/dmgbuild" \
  -s "$SETTINGS" \
  -D "app=$STAGE/source/CaptionPeel.app" \
  -D "background=$BACKGROUND" \
  "CaptionPeel" \
  "$DMG_OUT"

echo "wrote $DMG_OUT"
