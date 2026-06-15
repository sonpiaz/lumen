#!/bin/bash
# Pack dist/Lumen.app into a drag-to-Applications .dmg.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP="dist/Lumen.app"
DMG="dist/Lumen.dmg"
[ -d "$APP" ] || { echo "✗ build first: ./scripts/build-app.sh release"; exit 1; }

STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "Lumen" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"
echo "✓ $DMG"
