#!/bin/bash
# Builds Vitals.app — a menu-bar macOS bundle around the SPM executable.
# Usage: ./scripts/build-app.sh [debug|release]
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Pulse"
BUNDLE_ID="com.sonpiaz.pulse"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "▶ swift build -c $CONFIG"
swift build -c "$CONFIG"
BIN="$ROOT/.build/$CONFIG/$APP_NAME"
[ -f "$BIN" ] || { echo "✗ binary not found at $BIN"; exit 1; }

echo "▶ assembling $APP"
rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BIN" "$MACOS/$APP_NAME"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Prefer a stable Apple Development identity so the app keeps a consistent
# code identity across rebuilds (login items, etc.). Falls back to ad-hoc.
SIGN_IDENTITY="${VITALS_SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -oE '"Apple Development: [^"]+"' | head -1 | tr -d '"')"
fi

if [ -n "$SIGN_IDENTITY" ]; then
  echo "▶ codesign with: $SIGN_IDENTITY"
  codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP"
else
  echo "▶ ad-hoc codesign"
  codesign --force --sign - "$APP" >/dev/null 2>&1 || true
fi

echo "✓ built $APP"
echo "  run:  open \"$APP\""
