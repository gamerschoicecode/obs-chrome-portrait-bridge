# OBS Chrome Portrait Bridge

Menu-bar Mac app that captures **OBS Virtual Camera** through AVFoundation and serves full portrait frames to Chrome on `http://127.0.0.1:5199`.

Chrome’s `getUserMedia` cannot open OBS at the real canvas size ([obs-studio#13559](https://github.com/obsproject/obs-studio/issues/13559)). Restream / TikTok Live Studio use native capture; this app does the same and exposes JPEG frames for Streamline Card in view.

## Install (private DMG)

1. Download the latest `OBS-Chrome-Portrait-Bridge-*.dmg` from [Releases](https://github.com/gamerschoicecode/obs-chrome-portrait-bridge/releases) (private repo — must be logged into GitHub).
2. Open the DMG → drag **OBS Chrome Portrait Bridge** into **Applications**.
3. First launch: **Right-click → Open** (app is ad-hoc signed, not Apple-notarized).
4. Allow **Camera** when macOS asks.
5. In OBS **Settings → Video**, set **Base (Canvas)** and **Output (Scaled)** to the same portrait size (e.g. **1080×1920**). If Output is `360×640`, Virtual Camera only publishes that downscale — the bridge cannot invent pixels.
6. Start Virtual Camera, then leave the menu-bar item `OBS↕` running. The status menu shows the live frame size (should match Output, ideally `1080×1920`).

## Health API

| Path | Purpose |
|---|---|
| `GET /health` | `{ ok, version, protocol, width, height, ageMs, source, status }` |
| `GET /version` | `{ version, protocol, app }` |
| `GET /frame.jpg` | Latest JPEG frame |

Streamline expects `version` to match the pinned bridge version. A mismatch or offline bridge shows a badge with a redownload prompt.

## Develop

```bash
./scripts/build-app.sh
open "dist/OBS Chrome Portrait Bridge.app"

./scripts/make-dmg.sh
# → dist/OBS-Chrome-Portrait-Bridge-1.0.0.dmg

# Private GitHub release (requires gh auth as mshih-gc):
./scripts/release.sh
```

Override port with `OBS_BRIDGE_PORT=5200`.

## Version

See `version.json`. Bump it whenever you ship a DMG Streamline should require.
