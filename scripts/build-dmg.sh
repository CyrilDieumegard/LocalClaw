#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="LocalClaw"
DMG_NAME="localclaw"
BUNDLE_ID="io.localclaw.installer"
VERSION="1.0.0"
APP_PATH="dist/${APP_NAME}.app"
DMG_PATH="dist/${DMG_NAME}.dmg"
STAGING="dist/dmg-staging"

echo "[1/6] Building release binary"
swift build -c release

echo "[2/6] Preparing .app bundle"
rm -rf "$APP_PATH"
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
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

if [[ -n "${DEVELOPER_ID_APP:-}" ]]; then
  echo "[3/6] Signing app with Developer ID"
  codesign --force --options runtime --timestamp --deep --sign "$DEVELOPER_ID_APP" "$APP_PATH"
else
  echo "[3/6] Signing app ad-hoc (DEV MODE). For public release set DEVELOPER_ID_APP."
  codesign --force --deep --sign - "$APP_PATH"
fi

echo "[4/6] Building DMG"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG_PATH"
hdiutil create -volname "LocalClaw" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"

if [[ -n "${DEVELOPER_ID_APP:-}" ]]; then
  echo "[5/6] Signing DMG"
  codesign --force --timestamp --sign "$DEVELOPER_ID_APP" "$DMG_PATH"
else
  echo "[5/6] Skipping DMG signing (DEV MODE)"
fi

if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" && -n "${DEVELOPER_ID_APP:-}" ]]; then
  echo "[6/6] Notarizing DMG"
  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait
  xcrun stapler staple "$APP_PATH"
  xcrun stapler staple "$DMG_PATH"
  echo "Notarization complete and staples applied"
else
  echo "[6/6] Skipping notarization (missing Apple credentials)"
fi

echo "Built: $DMG_PATH"
