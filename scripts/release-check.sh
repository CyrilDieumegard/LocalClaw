#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_PATH="dist/LocalClawInstaller.app"
DMG_PATH="dist/localclaw.dmg"

echo "== LocalClaw release check =="

echo "[1] swift test"
swift test

echo "[2] swift build -c release"
swift build -c release

echo "[3] build dmg"
bash scripts/build-dmg.sh

echo "[4] binary info"
file .build/release/localclaw-mac-installer

echo "[5] codesign app"
codesign -dv --verbose=4 "$APP_PATH" 2>&1 | sed -n '1,25p'

echo "[6] app assessment (if spctl available)"
if command -v spctl >/dev/null 2>&1; then
  spctl -a -vv "$APP_PATH" || true
  spctl -a -vv "$DMG_PATH" || true
else
  echo "spctl not available in this environment"
fi

echo "[7] artifact sizes"
du -h "$APP_PATH" "$DMG_PATH"

echo "Release check complete"
