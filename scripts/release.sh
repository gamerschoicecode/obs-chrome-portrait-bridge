#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(python3 -c 'import json; print(json.load(open("version.json"))["version"])')"
TAG="v$VERSION"
DMG="$ROOT/dist/OBS-Chrome-Portrait-Bridge-$VERSION.dmg"

"$ROOT/scripts/build-app.sh"
"$ROOT/scripts/make-dmg.sh"

gh release view "$TAG" >/dev/null 2>&1 && EXISTS=1 || EXISTS=0
if [[ "$EXISTS" -eq 0 ]]; then
  gh release create "$TAG" "$DMG" \
    --title "$TAG" \
    --notes "$(cat <<EOF
## OBS Chrome Portrait Bridge $VERSION

Private unsigned DMG for desk Macs.

### Install
1. Download the DMG from this release
2. Open the DMG and drag **OBS Chrome Portrait Bridge** into Applications
3. First launch: Right-click the app → **Open** (unsigned / not notarized)
4. Allow Camera access when prompted
5. Start OBS → Start Virtual Camera
6. Leave the menu-bar app running (status item \`OBS↕\`)
7. Menu → **Copy auth token**, paste once in Streamline Card in view

### Chrome / Streamline
Card in view probes \`http://127.0.0.1:5199/health\` (Bearer token required) for \`version\` \`$VERSION\`.
EOF
)"
else
  gh release upload "$TAG" "$DMG" --clobber
fi

echo "Published $TAG"
gh release view "$TAG" --json url,assets -q '{url:.url, assets:[.assets[].name]}'
