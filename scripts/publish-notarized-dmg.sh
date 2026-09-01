#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE_ROOT="${SITE_ROOT:-${ROOT}/../localclaw.io}"
DMG_PATH="${DMG_PATH:-${ROOT}/dist/localclaw.dmg}"
DOWNLOADS_DIR="${DOWNLOADS_DIR:-${SITE_ROOT}/downloads}"
MANIFEST_PATH="${MANIFEST_PATH:-${DOWNLOADS_DIR}/localclaw-installer-latest.json}"
EXPECTED_TEAM_ID="923MBLC4X4"
EXPECTED_BUNDLE_ID="io.localclaw.installer"
PUBLIC_MANIFEST_URL="${LOCALCLAW_PUBLIC_MANIFEST_URL:-https://localclaw.io/downloads/localclaw-installer-latest.json}"
PUBLIC_DOWNLOAD_BASE_URL="${LOCALCLAW_PUBLIC_DOWNLOAD_BASE_URL:-https://raw.githubusercontent.com/CyrilDieumegard/localclaw.io/main/downloads}"
CURL_BIN="${LOCALCLAW_CURL_BIN:-/usr/bin/curl}"
NETWORK_TIMEOUT_SECONDS="${LOCALCLAW_PUBLISH_NETWORK_TIMEOUT_SECONDS:-20}"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "Missing DMG: $DMG_PATH"
  exit 1
fi

if [[ ! -d "$DOWNLOADS_DIR" ]]; then
  echo "Missing downloads directory: $DOWNLOADS_DIR"
  exit 1
fi
if [[ ! -x "$CURL_BIN" ]]; then
  echo "Missing executable curl client: $CURL_BIN" >&2
  exit 1
fi
if ! CURL_VERSION_OUTPUT="$("$CURL_BIN" --version 2>/dev/null)"; then
  echo "Unable to run curl version check: $CURL_BIN" >&2
  exit 1
fi
CURL_VERSION_RAW="${CURL_VERSION_OUTPUT%%$'\n'*}"
if [[ ! "$CURL_VERSION_RAW" =~ ^curl[[:space:]]+([0-9]+)\.([0-9]+)\. ]]; then
  echo "Unable to determine curl version from: $CURL_VERSION_RAW" >&2
  exit 1
fi
CURL_VERSION_MAJOR="${BASH_REMATCH[1]}"
CURL_VERSION_MINOR="${BASH_REMATCH[2]}"
if (( CURL_VERSION_MAJOR < 8 || (CURL_VERSION_MAJOR == 8 && CURL_VERSION_MINOR < 4) )); then
  echo "Publish requires curl 8.4 or newer so the GET probe byte ceiling is enforced during transfer." >&2
  exit 1
fi
if [[ ! "$NETWORK_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
  echo "Publish network timeout must be a positive integer." >&2
  exit 1
fi
if [[ "$PUBLIC_MANIFEST_URL" != https://* || "$PUBLIC_DOWNLOAD_BASE_URL" != https://* ]]; then
  echo "Public manifest and download URLs must use HTTPS." >&2
  exit 1
fi

DOWNLOADS_REAL="$(cd "$DOWNLOADS_DIR" && pwd -P)"
MANIFEST_DIR="$(dirname "$MANIFEST_PATH")"
if [[ ! -d "$MANIFEST_DIR" ]]; then
  echo "Missing manifest directory: $MANIFEST_DIR" >&2
  exit 1
fi
MANIFEST_DIR_REAL="$(cd "$MANIFEST_DIR" && pwd -P)"
if [[ "$MANIFEST_DIR_REAL" != "$DOWNLOADS_REAL" ]]; then
  echo "Manifest must be published inside the downloads directory: $DOWNLOADS_REAL" >&2
  exit 1
fi
if [[ -d "$MANIFEST_PATH" ]]; then
  echo "Manifest path is a directory: $MANIFEST_PATH" >&2
  exit 1
fi

CACHE_BUST_RUN="$(date -u +%s)-$$-${RANDOM}"
with_cache_buster() {
  local url="$1"
  local value="$2"
  local base="$url"
  local fragment=""
  local separator="?"

  if [[ "$base" == *"#"* ]]; then
    fragment="#${base#*#}"
    base="${base%%#*}"
  fi
  if [[ "$base" == *"?"* ]]; then
    separator="&"
  fi
  printf '%s%s_localclaw_cb=%s%s' "$base" "$separator" "$value" "$fragment"
}

CHECK_ROOT="$(mktemp -d /private/tmp/localclaw-publish-check.XXXXXX)"
MOUNT_DIR="$CHECK_ROOT/mount"
CHECK_DMG="$CHECK_ROOT/localclaw.dmg"
PUBLISH_STAGE=""
MOUNTED=0
cleanup() {
  if [[ "$MOUNTED" == "1" ]]; then
    hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || hdiutil detach "$MOUNT_DIR" -force -quiet >/dev/null 2>&1 || true
  fi
  if [[ -n "${PUBLISH_STAGE:-}" ]]; then
    rm -rf "$PUBLISH_STAGE"
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

echo "[1/8] Validating signed and stapled DMG snapshot"
codesign --verify --strict --verbose=2 "$CHECK_DMG"
xcrun stapler validate "$CHECK_DMG"
spctl -a -vv -t open --context context:primary-signature "$CHECK_DMG"
DMG_TEAM_ID="$(codesign -dv --verbose=4 "$CHECK_DMG" 2>&1 | awk -F= '$1 == "TeamIdentifier" { print $2; exit }')"
if [[ "$DMG_TEAM_ID" != "$EXPECTED_TEAM_ID" ]]; then
  echo "Unexpected DMG signing team: ${DMG_TEAM_ID:-none}" >&2
  exit 1
fi

echo "[2/8] Validating app inside DMG"
# Mount a byte-identical scratch copy so hdiutil cannot add Finder metadata to
# the signed DMG that will be copied into the downloads directory.
hdiutil attach "$CHECK_DMG" -readonly -nobrowse -quiet -mountpoint "$MOUNT_DIR"
MOUNTED=1
PACKAGED_APP="$MOUNT_DIR/LocalClaw.app"
if [[ ! -d "$PACKAGED_APP" ]]; then
  echo "LocalClaw.app is missing from the DMG." >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$PACKAGED_APP"
spctl -a -t exec -vv "$PACKAGED_APP"
APP_TEAM_ID="$(codesign -dv --verbose=4 "$PACKAGED_APP" 2>&1 | awk -F= '$1 == "TeamIdentifier" { print $2; exit }')"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PACKAGED_APP/Contents/Info.plist")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PACKAGED_APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PACKAGED_APP/Contents/Info.plist")"

if [[ "$APP_TEAM_ID" != "$EXPECTED_TEAM_ID" ]]; then
  echo "Unexpected app signing team: ${APP_TEAM_ID:-none}" >&2
  exit 1
fi
if [[ "$BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]]; then
  echo "Unexpected app bundle identifier: $BUNDLE_ID" >&2
  exit 1
fi
if [[ ! "$VERSION" =~ ^[0-9]+([.][0-9]+)*$ ]]; then
  echo "Invalid app version: $VERSION" >&2
  exit 1
fi
if [[ ! "$BUILD" =~ ^[1-9][0-9]*$ ]]; then
  echo "Invalid app build number: $BUILD" >&2
  exit 1
fi

hdiutil detach "$MOUNT_DIR" -quiet
MOUNTED=0

VERSIONED_NAME="localclaw-${VERSION}-${BUILD}.dmg"
VERSIONED_PATH="${DOWNLOADS_DIR}/${VERSIONED_NAME}"
LATEST_PATH="${DOWNLOADS_DIR}/localclaw.dmg"
PUBLIC_VERSIONED_URL="${PUBLIC_DOWNLOAD_BASE_URL%/}/${VERSIONED_NAME}"
PUBLIC_MANIFEST_SNAPSHOT="${CHECK_ROOT}/public-update-manifest.json"
PUBLIC_MANIFEST_FETCH_URL="$(with_cache_buster "$PUBLIC_MANIFEST_URL" "${CACHE_BUST_RUN}-manifest")"
PUBLIC_VERSIONED_HEAD_URL="$(with_cache_buster "$PUBLIC_VERSIONED_URL" "${CACHE_BUST_RUN}-artifact-head")"
PUBLIC_VERSIONED_GET_URL="$(with_cache_buster "$PUBLIC_VERSIONED_URL" "${CACHE_BUST_RUN}-artifact-get")"

echo "[3/8] Fetching current public release state"
if ! "$CURL_BIN" \
  --fail \
  --silent \
  --show-error \
  --location \
  --proto '=https' \
  --proto-redir '=https' \
  --max-time "$NETWORK_TIMEOUT_SECONDS" \
  --output "$PUBLIC_MANIFEST_SNAPSHOT" \
  "$PUBLIC_MANIFEST_FETCH_URL"; then
  echo "Unable to fetch the current public update manifest; refusing to publish." >&2
  exit 1
fi

echo "[4/8] Enforcing monotone local and public releases"
python3 - "$MANIFEST_PATH" "$PUBLIC_MANIFEST_SNAPSHOT" "$VERSION" "$BUILD" <<'PY'
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlparse

local_manifest_path = Path(sys.argv[1])
public_manifest_path = Path(sys.argv[2])
new_version = sys.argv[3]
new_build = int(sys.argv[4])

def version_parts(value):
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", value):
        raise SystemExit(f"Invalid release version: {value}")
    return tuple(int(part) for part in value.split("."))

def read_manifest(path, label):
    try:
        current = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(current, dict):
            raise ValueError("root must be an object")
        current_version = str(current["latestVersion"])
        current_build_raw = str(current["latestBuild"])
        if not re.fullmatch(r"[1-9][0-9]*", current_build_raw):
            raise ValueError(f"invalid current build: {current_build_raw}")
        current_build = int(current_build_raw)
        version_parts(current_version)
        current_sha = str(current["sha256"])
        if not re.fullmatch(r"[a-fA-F0-9]{64}", current_sha):
            raise ValueError("sha256 must contain 64 hexadecimal characters")
        current_dmg_url = str(current["dmgUrl"])
        if urlparse(current_dmg_url).scheme != "https":
            raise ValueError("dmgUrl must use HTTPS")
    except Exception as error:
        raise SystemExit(f"{label} update manifest is invalid; refusing to publish: {error}")
    return current_version, current_build

def enforce_newer(current_version, current_build, label):
    current_parts = list(version_parts(current_version))
    new_parts = list(version_parts(new_version))
    width = max(len(current_parts), len(new_parts))
    current_parts.extend([0] * (width - len(current_parts)))
    new_parts.extend([0] * (width - len(new_parts)))

    if new_parts < current_parts:
        raise SystemExit(
            f"Release version must not decrease from {label} {current_version}; got {new_version}."
        )
    if new_build <= current_build:
        raise SystemExit(
            f"Release build must be greater than {label} build {current_build}; got {new_build}."
        )

if local_manifest_path.exists():
    local_version, local_build = read_manifest(local_manifest_path, "Local")
    enforce_newer(local_version, local_build, "local")

public_version, public_build = read_manifest(public_manifest_path, "Public")
enforce_newer(public_version, public_build, "public")
PY

if ! PUBLIC_TARGET_STATUS="$("$CURL_BIN" \
  --silent \
  --show-error \
  --proto '=https' \
  --max-time "$NETWORK_TIMEOUT_SECONDS" \
  --head \
  --output /dev/null \
  --write-out '%{http_code}' \
  "$PUBLIC_VERSIONED_HEAD_URL")"; then
  echo "Unable to determine the public versioned URL with HEAD; refusing to publish." >&2
  exit 1
fi
if [[ "$PUBLIC_TARGET_STATUS" != "404" ]]; then
  echo "Public versioned URL HEAD must return exactly 404 before publication; got ${PUBLIC_TARGET_STATUS:-no status}: $PUBLIC_VERSIONED_URL" >&2
  exit 1
fi

# HEAD can disagree with GET on CDNs and object stores. Confirm absence with a
# cache-busted GET that requests one byte and aborts if the response would
# exceed one byte. Curl exit 63 is accepted only alongside HTTP 404: it means
# the explicit size ceiling stopped an oversized 404 response body.
PUBLIC_TARGET_GET_EXIT=0
PUBLIC_TARGET_GET_STATUS="$("$CURL_BIN" \
  --silent \
  --proto '=https' \
  --max-time "$NETWORK_TIMEOUT_SECONDS" \
  --range 0-0 \
  --max-filesize 1 \
  --output /dev/null \
  --write-out '%{http_code}' \
  "$PUBLIC_VERSIONED_GET_URL")" || PUBLIC_TARGET_GET_EXIT=$?
if [[ "$PUBLIC_TARGET_GET_STATUS" != "404" || ( "$PUBLIC_TARGET_GET_EXIT" != "0" && "$PUBLIC_TARGET_GET_EXIT" != "63" ) ]]; then
  echo "Public versioned URL GET must return exactly 404 within the one-byte probe limit; got ${PUBLIC_TARGET_GET_STATUS:-no status} (curl exit ${PUBLIC_TARGET_GET_EXIT}): $PUBLIC_VERSIONED_URL" >&2
  exit 1
fi

if [[ -e "$VERSIONED_PATH" || -L "$VERSIONED_PATH" ]]; then
  echo "Versioned release already exists: $VERSIONED_PATH" >&2
  exit 1
fi

PUBLISH_STAGE="$(mktemp -d "${DOWNLOADS_DIR}/.localclaw-publish.XXXXXX")"
STAGED_VERSIONED_PATH="${PUBLISH_STAGE}/${VERSIONED_NAME}"
STAGED_LATEST_PATH="${PUBLISH_STAGE}/localclaw.dmg"
STAGED_MANIFEST_PATH="${PUBLISH_STAGE}/localclaw-installer-latest.json"

echo "[5/8] Staging stapled DMG"
cp "$CHECK_DMG" "$STAGED_VERSIONED_PATH"
cp "$CHECK_DMG" "$STAGED_LATEST_PATH"

if ! cmp -s "$CHECK_DMG" "$STAGED_VERSIONED_PATH" || ! cmp -s "$CHECK_DMG" "$STAGED_LATEST_PATH"; then
  echo "A staged DMG differs from the artifact that passed validation." >&2
  exit 1
fi

echo "[6/8] Calculating sha256 after stapling"
SHA256="$(shasum -a 256 "$STAGED_VERSIONED_PATH" | awk '{print $1}')"

echo "[7/8] Writing and verifying staged update manifest"
python3 - "$STAGED_MANIFEST_PATH" "$VERSION" "$BUILD" "$PUBLIC_VERSIONED_URL" "$SHA256" <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
version = sys.argv[2]
build = sys.argv[3]
dmg_url = sys.argv[4]
sha256 = sys.argv[5]

manifest = {
    "latestVersion": version,
    "latestBuild": build,
    "dmgUrl": dmg_url,
    "notesUrl": f"https://localclaw.io/changelog/localclaw-installer-v{version}",
    "sha256": sha256,
}
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
PY

python3 -m json.tool "$STAGED_MANIFEST_PATH" >/dev/null
MANIFEST_SHA="$(python3 - "$STAGED_MANIFEST_PATH" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["sha256"])
PY
)"
if [[ "$MANIFEST_SHA" != "$SHA256" ]]; then
  echo "Manifest sha256 mismatch"
  exit 1
fi

if ! cmp -s "$STAGED_VERSIONED_PATH" "$STAGED_LATEST_PATH"; then
  echo "Staged latest DMG differs from the versioned artifact." >&2
  exit 1
fi

echo "[8/8] Publishing artifacts; manifest is committed last"
# The stage directory lives on the downloads filesystem. Creating a hard link
# is therefore an atomic no-clobber commit: it fails if any file, directory, or
# symlink appeared at the immutable versioned path after the earlier check.
if ! /bin/ln "$STAGED_VERSIONED_PATH" "$VERSIONED_PATH"; then
  echo "Versioned release appeared during publication; refusing to overwrite it: $VERSIONED_PATH" >&2
  exit 1
fi
/bin/rm "$STAGED_VERSIONED_PATH"
if ! cmp -s "$CHECK_DMG" "$VERSIONED_PATH"; then
  echo "Published versioned DMG differs from the validated artifact." >&2
  exit 1
fi
mv "$STAGED_LATEST_PATH" "$LATEST_PATH"
mv "$STAGED_MANIFEST_PATH" "$MANIFEST_PATH"

echo "Published files prepared:"
echo "  ${VERSIONED_PATH}"
echo "  ${LATEST_PATH}"
echo "  ${MANIFEST_PATH}"
echo "  sha256=${SHA256}"
