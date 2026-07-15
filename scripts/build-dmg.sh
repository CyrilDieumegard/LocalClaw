#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="LocalClaw"
DMG_NAME="localclaw"
BUNDLE_ID="io.localclaw.installer"
MARKETING_VERSION="1.0.167"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
DIST_DIR="dist"
DIST_APP_PATH="${DIST_DIR}/${APP_NAME}.app"
DIST_DMG_PATH="${DIST_DIR}/${DMG_NAME}.dmg"
DEVELOPER_ID_APP="${DEVELOPER_ID_APP:-Developer ID Application: Cyril Dieumegard (923MBLC4X4)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-localclaw-notary}"
RELEASE_NOTARIZE="${RELEASE_NOTARIZE:-0}"
NOTARY_TIMEOUT_SECONDS="${NOTARY_TIMEOUT_SECONDS:-900}"
NOTARY_POLL_SECONDS="${NOTARY_POLL_SECONDS:-15}"

mkdir -p "$DIST_DIR"
if [[ "$RELEASE_NOTARIZE" == "1" ]]; then
  BUILD_ROOT="$(mktemp -d /private/tmp/localclaw-release.XXXXXX)"
  trap 'rm -rf "$BUILD_ROOT"' EXIT
else
  BUILD_ROOT="$DIST_DIR"
fi
APP_PATH="${BUILD_ROOT}/${APP_NAME}.app"
DMG_PATH="${BUILD_ROOT}/${DMG_NAME}.dmg"
STAGING="${BUILD_ROOT}/dmg-staging"

is_macho_file() {
  local path="$1"
  file "$path" 2>/dev/null | grep -Eq 'Mach-O|ar archive random library'
}

strip_macos_detritus() {
  local path="$1"
  xattr -cr "$path" 2>/dev/null || true
  while IFS= read -r item; do
    xattr -d com.apple.FinderInfo "$item" 2>/dev/null || true
    xattr -d 'com.apple.fileprovider.fpfs#P' "$item" 2>/dev/null || true
    xattr -d com.apple.provenance "$item" 2>/dev/null || true
  done < <(find "$path" -print)
}

sign_code_path() {
  local path="$1"
  echo "  signing ${path}"
  strip_macos_detritus "$path"
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APP" "$path"
}

sign_app_bundle() {
  echo "  inspecting bundle contents"

  while IFS= read -r nested; do
    if is_macho_file "$nested"; then
      sign_code_path "$nested"
    fi
  done < <(find "$APP_PATH/Contents" \( -path "*/_CodeSignature/*" -o -path "*/CodeResources" \) -prune -o -type f -perm -111 -print | sort)

  while IFS= read -r nested; do
    if is_macho_file "$nested"; then
      sign_code_path "$nested"
    fi
  done < <(find "$APP_PATH/Contents" \( -path "*/_CodeSignature/*" -o -path "*/CodeResources" \) -prune -o -type f \( -name "*.dylib" -o -name "*.so" -o -name "*.a" \) -print | sort)

  while IFS= read -r nested; do
    if [ -d "$nested/Versions" ] || find "$nested" -maxdepth 3 -type f -perm -111 | grep -q .; then
      sign_code_path "$nested"
    fi
  done < <(find "$APP_PATH/Contents" -type d \( -name "*.framework" -o -name "*.xpc" -o -name "*.appex" -o -name "*.plugin" \) -print | sort)

  strip_macos_detritus "$APP_PATH"
  echo "  signing app bundle"
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APP" "$APP_PATH"
  codesign --verify --strict --verbose=2 "$APP_PATH"
}

notarize_and_staple_dmg() {
  local output submission_id status elapsed info_output

  echo "  submitting ${DMG_PATH} with keychain profile ${NOTARY_PROFILE}"
  if ! output="$(xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" 2>&1)"; then
    echo "$output"
    submission_id="$(printf '%s\n' "$output" | awk -F ': ' '/^[[:space:]]*id:/ {print $2; exit}')"
    if [[ -n "$submission_id" ]]; then
      echo "  fetching notarization log for ${submission_id}"
      xcrun notarytool log "$submission_id" --keychain-profile "$NOTARY_PROFILE" || true
    fi
    exit 1
  fi

  echo "$output"
  submission_id="$(printf '%s\n' "$output" | awk -F ': ' '/^[[:space:]]*id:/ {print $2; exit}')"
  if [[ -z "$submission_id" ]]; then
    echo "Notarization submission did not return a submission id."
    exit 1
  fi

  elapsed=0
  status=""
  while (( elapsed <= NOTARY_TIMEOUT_SECONDS )); do
    info_output="$(xcrun notarytool info "$submission_id" --keychain-profile "$NOTARY_PROFILE" 2>&1 || true)"
    echo "$info_output"
    status="$(printf '%s\n' "$info_output" | awk -F ': ' '/^[[:space:]]*status:/ {print $2; exit}')"
    case "$status" in
      Accepted|Invalid|Rejected)
        break
        ;;
    esac
    sleep "$NOTARY_POLL_SECONDS"
    elapsed=$((elapsed + NOTARY_POLL_SECONDS))
  done

  if [[ "$status" != "Accepted" ]]; then
    echo "Notarization failed, timed out, or was not accepted. Status: ${status:-unknown}. Submission id: ${submission_id}"
    echo "Notarization log:"
    xcrun notarytool log "$submission_id" --keychain-profile "$NOTARY_PROFILE" || true
    exit 1
  fi

  echo "  stapling DMG"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
}

echo "[1/6] Building release binary"
swift build -c release

echo "[2/6] Preparing .app bundle"
rm -rf "$APP_PATH" "$DIST_APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources" "$STAGING"
cp .build/release/localclaw-mac-installer "$APP_PATH/Contents/MacOS/${APP_NAME}"
chmod +x "$APP_PATH/Contents/MacOS/${APP_NAME}"

if [ -d .build/release/localclaw-mac-installer_localclaw-mac-installer.bundle ]; then
  cp -R .build/release/localclaw-mac-installer_localclaw-mac-installer.bundle "$APP_PATH/Contents/Resources/"
fi

# Ship LocalClaw logo as direct app resource (used by UI and app icon generation)
if [ -f "Sources/Resources/localclaw-logo.png" ]; then
  cp "Sources/Resources/localclaw-logo.png" "$APP_PATH/Contents/Resources/localclaw-logo.png"
fi

# Build .icns from localclaw-logo.png when possible
if command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1 && [ -f "$APP_PATH/Contents/Resources/localclaw-logo.png" ]; then
  ICONSET_DIR="dist/AppIcon.iconset"
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"

  sips -z 16 16   "$APP_PATH/Contents/Resources/localclaw-logo.png" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null 2>&1 || true
  sips -z 32 32   "$APP_PATH/Contents/Resources/localclaw-logo.png" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null 2>&1 || true
  sips -z 32 32   "$APP_PATH/Contents/Resources/localclaw-logo.png" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null 2>&1 || true
  sips -z 64 64   "$APP_PATH/Contents/Resources/localclaw-logo.png" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null 2>&1 || true
  sips -z 128 128 "$APP_PATH/Contents/Resources/localclaw-logo.png" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null 2>&1 || true
  sips -z 256 256 "$APP_PATH/Contents/Resources/localclaw-logo.png" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null 2>&1 || true
  sips -z 256 256 "$APP_PATH/Contents/Resources/localclaw-logo.png" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null 2>&1 || true
  sips -z 512 512 "$APP_PATH/Contents/Resources/localclaw-logo.png" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null 2>&1 || true
  sips -z 512 512 "$APP_PATH/Contents/Resources/localclaw-logo.png" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null 2>&1 || true
  cp "$APP_PATH/Contents/Resources/localclaw-logo.png" "$ICONSET_DIR/icon_512x512@2x.png"

  iconutil -c icns "$ICONSET_DIR" -o "$APP_PATH/Contents/Resources/AppIcon.icns" >/dev/null 2>&1 || true
  rm -rf "$ICONSET_DIR"
fi

cat > "$APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>LocalClaw</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

CLEAN_APP_PATH="${APP_PATH}.clean"
rm -rf "$CLEAN_APP_PATH"
ditto --noextattr --noacl "$APP_PATH" "$CLEAN_APP_PATH"
rm -rf "$APP_PATH"
mv "$CLEAN_APP_PATH" "$APP_PATH"
strip_macos_detritus "$APP_PATH"

if [[ "$RELEASE_NOTARIZE" == "1" ]]; then
  echo "[3/6] Signing app with Developer ID"
  sign_app_bundle
else
  echo "[3/6] Signing app ad-hoc (DEV MODE). For public release set DEVELOPER_ID_APP."
  codesign --force --deep --sign - "$APP_PATH"
fi

echo "[4/6] Building DMG"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG_PATH" "$DIST_DMG_PATH"
hdiutil create -volname "LocalClaw" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"

if [[ "$RELEASE_NOTARIZE" == "1" ]]; then
  echo "[5/6] Signing DMG"
  codesign --force --timestamp --sign "$DEVELOPER_ID_APP" "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
else
  echo "[5/6] Skipping DMG signing (DEV MODE)"
fi

if [[ "$RELEASE_NOTARIZE" == "1" ]]; then
  echo "[6/6] Notarizing and stapling DMG"
  notarize_and_staple_dmg
  echo "Notarization complete and DMG staple validated"
else
  echo "[6/6] Skipping notarization (DEV MODE). For public release set RELEASE_NOTARIZE=1."
fi

if [[ "$APP_PATH" != "$DIST_APP_PATH" ]]; then
  echo "Copying release artifacts to ${DIST_DIR}"
  rm -rf "$DIST_APP_PATH"
  ditto --noextattr --noacl "$APP_PATH" "$DIST_APP_PATH"
  cp "$DMG_PATH" "$DIST_DMG_PATH"
fi

echo "Built: $DIST_DMG_PATH"
