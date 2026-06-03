#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE_ROOT="${SITE_ROOT:-${ROOT}/../localclaw.io}"
APP_PATH="${APP_PATH:-${ROOT}/dist/LocalClaw.app}"
DMG_PATH="${DMG_PATH:-${ROOT}/dist/localclaw.dmg}"
DOWNLOADS_DIR="${DOWNLOADS_DIR:-${SITE_ROOT}/downloads}"
MANIFEST_PATH="${MANIFEST_PATH:-${DOWNLOADS_DIR}/localclaw-installer-latest.json}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing app bundle: $APP_PATH"
  exit 1
fi

if [[ ! -f "$DMG_PATH" ]]; then
  echo "Missing DMG: $DMG_PATH"
  exit 1
fi

if [[ ! -d "$DOWNLOADS_DIR" ]]; then
  echo "Missing downloads directory: $DOWNLOADS_DIR"
  exit 1
fi

echo "[1/5] Validating stapled DMG"
xcrun stapler validate "$DMG_PATH"
spctl -a -vv -t open --context context:primary-signature "$DMG_PATH"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
VERSIONED_NAME="localclaw-${VERSION}.dmg"
VERSIONED_PATH="${DOWNLOADS_DIR}/${VERSIONED_NAME}"
LATEST_PATH="${DOWNLOADS_DIR}/localclaw.dmg"

echo "[2/5] Copying stapled DMG"
cp "$DMG_PATH" "$VERSIONED_PATH"
cp "$DMG_PATH" "$LATEST_PATH"

echo "[3/5] Calculating sha256 after stapling"
SHA256="$(shasum -a 256 "$VERSIONED_PATH" | awk '{print $1}')"

echo "[4/5] Writing update manifest"
python3 - "$MANIFEST_PATH" "$VERSION" "$BUILD" "$VERSIONED_NAME" "$SHA256" <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
version = sys.argv[2]
build = sys.argv[3]
dmg_name = sys.argv[4]
sha256 = sys.argv[5]

manifest = {
    "latestVersion": version,
    "latestBuild": build,
    "dmgUrl": f"https://raw.githubusercontent.com/CyrilDieumegard/localclaw.io/main/downloads/{dmg_name}",
    "notesUrl": f"https://localclaw.io/changelog/localclaw-installer-v{version}",
    "sha256": sha256,
}
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
PY

echo "[5/5] Verifying manifest sha256"
python3 -m json.tool "$MANIFEST_PATH" >/dev/null
MANIFEST_SHA="$(python3 - "$MANIFEST_PATH" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["sha256"])
PY
)"
if [[ "$MANIFEST_SHA" != "$SHA256" ]]; then
  echo "Manifest sha256 mismatch"
  exit 1
fi

echo "Published files prepared:"
echo "  ${VERSIONED_PATH}"
echo "  ${LATEST_PATH}"
echo "  ${MANIFEST_PATH}"
echo "  sha256=${SHA256}"
