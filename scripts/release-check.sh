#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_PATH="dist/LocalClaw.app"
DMG_PATH="dist/localclaw.dmg"
EXPECTED_TEAM_ID="923MBLC4X4"
EXPECTED_BUNDLE_ID="io.localclaw.installer"

if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  echo "Release blocked: the Git working tree must be clean, including untracked files." >&2
  exit 1
fi

if [[ "${RELEASE_NOTARIZE:-}" != "1" ]]; then
  echo "Release blocked: run with RELEASE_NOTARIZE=1." >&2
  exit 1
fi

if [[ ! "${LOCALCLAW_BUILD_NUMBER:-}" =~ ^[1-9][0-9]*$ ]]; then
  echo "Release blocked: set LOCALCLAW_BUILD_NUMBER to a positive integer." >&2
  exit 1
fi

if [[ -z "${OPENCLAW_PACKAGE_ROOT:-}" || ! -f "${OPENCLAW_PACKAGE_ROOT}/openclaw.mjs" ]]; then
  echo "Release blocked: set OPENCLAW_PACKAGE_ROOT to the verified OpenClaw 2.0 package used for compatibility tests." >&2
  exit 1
fi

echo "== LocalClaw release check =="

echo "[1] release preflight"
echo "  clean tree: yes"
echo "  notarized build: yes"
echo "  build number: ${LOCALCLAW_BUILD_NUMBER}"
echo "  OpenClaw fixture: ${OPENCLAW_PACKAGE_ROOT}"

echo "[2] OpenClaw 2.0 compatibility"
node --check Sources/Resources/goal-controller.mjs
node scripts/test-goal-controller-contract.mjs
node scripts/test-openclaw-compat.mjs "$OPENCLAW_PACKAGE_ROOT"
node scripts/test-openclaw-exec-migration.mjs "$OPENCLAW_PACKAGE_ROOT"
node scripts/test-openclaw-turn.mjs "$OPENCLAW_PACKAGE_ROOT" --gateway --legacy-config
node scripts/test-openclaw-post-update.mjs "$OPENCLAW_PACKAGE_ROOT"
node scripts/test-openclaw-update-owner.mjs "$OPENCLAW_PACKAGE_ROOT" --legacy-config

echo "[3] swift test"
swift test --scratch-path /private/tmp/localclaw-release-swift -j 1

echo "[4] build, sign, notarize and staple DMG"
RELEASE_NOTARIZE=1 LOCALCLAW_BUILD_NUMBER="$LOCALCLAW_BUILD_NUMBER" bash scripts/build-dmg.sh

echo "[5] binary info"
file .build/release/localclaw-mac-installer

if [[ ! -d "$APP_PATH" || ! -f "$DMG_PATH" ]]; then
  echo "Release artifacts are missing after the notarized build." >&2
  exit 1
fi

EXPECTED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
DIST_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
if [[ -z "$EXPECTED_VERSION" || "$DIST_BUILD" != "$LOCALCLAW_BUILD_NUMBER" ]]; then
  echo "Release metadata mismatch in the staged app." >&2
  exit 1
fi

echo "[6] signed, stapled DMG assessment"
codesign --verify --strict --verbose=2 "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
if command -v spctl >/dev/null 2>&1; then
  spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"
else
  echo "spctl is required for a release check" >&2
  exit 1
fi

DMG_TEAM_ID="$(codesign -dv --verbose=4 "$DMG_PATH" 2>&1 | awk -F= '$1 == "TeamIdentifier" { print $2; exit }')"
if [[ "$DMG_TEAM_ID" != "$EXPECTED_TEAM_ID" ]]; then
  echo "Unexpected DMG signing team: ${DMG_TEAM_ID:-none}" >&2
  exit 1
fi

CHECK_ROOT="$(mktemp -d /private/tmp/localclaw-release-check.XXXXXX)"
MOUNT_DIR="$CHECK_ROOT/mount"
CHECK_DMG="$CHECK_ROOT/localclaw.dmg"
MOUNTED=0
cleanup() {
  if [[ "$MOUNTED" == "1" ]]; then
    hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || hdiutil detach "$MOUNT_DIR" -force -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$CHECK_ROOT"
}
trap cleanup EXIT
mkdir -p "$MOUNT_DIR"
cp "$DMG_PATH" "$CHECK_DMG"
if ! cmp -s "$DMG_PATH" "$CHECK_DMG"; then
  echo "Temporary DMG copy differs from the release artifact." >&2
  exit 1
fi

echo "[7] app inside final DMG"
# Mount a byte-identical scratch copy because hdiutil may add Finder metadata
# to the image file it opens, which must never mutate the signed release DMG.
hdiutil attach "$CHECK_DMG" -readonly -nobrowse -quiet -mountpoint "$MOUNT_DIR"
MOUNTED=1
PACKAGED_APP="$MOUNT_DIR/LocalClaw.app"
if [[ ! -d "$PACKAGED_APP" ]]; then
  echo "LocalClaw.app is missing from the final DMG." >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$PACKAGED_APP"
spctl -a -t exec -vv "$PACKAGED_APP"
APP_TEAM_ID="$(codesign -dv --verbose=4 "$PACKAGED_APP" 2>&1 | awk -F= '$1 == "TeamIdentifier" { print $2; exit }')"
APP_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PACKAGED_APP/Contents/Info.plist")"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PACKAGED_APP/Contents/Info.plist")"
APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PACKAGED_APP/Contents/Info.plist")"

if [[ "$APP_TEAM_ID" != "$EXPECTED_TEAM_ID" ]]; then
  echo "Unexpected app signing team: ${APP_TEAM_ID:-none}" >&2
  exit 1
fi
if [[ "$APP_BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]]; then
  echo "Unexpected app bundle identifier: $APP_BUNDLE_ID" >&2
  exit 1
fi
if [[ "$APP_VERSION" != "$EXPECTED_VERSION" || "$APP_BUILD" != "$LOCALCLAW_BUILD_NUMBER" ]]; then
  echo "Final DMG app metadata mismatch: ${APP_VERSION} (${APP_BUILD})." >&2
  exit 1
fi

echo "[8] artifact sizes"
du -h "$APP_PATH" "$DMG_PATH"

echo "Release check complete"
