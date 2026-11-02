#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(python3 -c 'import json; print(json.load(open("version.json"))["version"])')"
APP_NAME="OBS Chrome Portrait Bridge"
APP="$ROOT/dist/$APP_NAME.app"
STAGE="$ROOT/dist/dmg-root"
DMG="$ROOT/dist/OBS-Chrome-Portrait-Bridge-$VERSION.dmg"

if [[ ! -d "$APP" ]]; then
  "$ROOT/scripts/build-app.sh"
fi

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Simple unsigned / ad-hoc DMG for private installs.
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG"

rm -rf "$STAGE"
echo "DMG ready: $DMG"
ls -lh "$DMG"
