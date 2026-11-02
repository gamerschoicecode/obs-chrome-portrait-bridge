#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(python3 -c 'import json; print(json.load(open("version.json"))["version"])')"
DIST="$ROOT/dist"
APP_NAME="OBS Chrome Portrait Bridge"
APP="$DIST/$APP_NAME.app"
MACOS="$APP/Contents/MacOS"
BIN="$MACOS/ObsChromePortraitBridge"

rm -rf "$APP"
mkdir -p "$MACOS" "$APP/Contents/Resources"

echo "Compiling ${APP_NAME} v${VERSION}..."
swiftc -O \
  -target arm64-apple-macosx14.0 \
  Sources/ObsChromePortraitBridge/*.swift \
  -framework AppKit \
  -framework AVFoundation \
  -framework CoreImage \
  -framework CoreMedia \
  -framework CoreVideo \
  -framework Foundation \
  -o "$BIN"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist" >/dev/null

# Ad-hoc signature so Gatekeeper has something to attach TCC to.
# Not notarized — first launch still needs Right-click → Open.
codesign --force --deep --sign - "$APP"

echo "Built $APP"
echo "$APP"
