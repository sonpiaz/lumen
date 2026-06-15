#!/bin/bash
# Regenerate icon/Lumen.icns. Re-renders the IconView from the built binary when
# available, then packs every required size into the .icns via iconutil.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p icon
MASTER="$ROOT/icon/Lumen-1024.png"

if [ -x "$ROOT/.build/release/Lumen" ]; then
  "$ROOT/.build/release/Lumen" --render-icon "$MASTER" >/dev/null 2>&1 || true
fi
[ -f "$MASTER" ] || { echo "✗ master PNG missing: $MASTER"; exit 1; }

TMP="$(mktemp -d)"
ICONSET="$TMP/Lumen.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" "$MASTER" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z "$d" "$d" "$MASTER" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT/icon/Lumen.icns"
rm -rf "$TMP"
echo "✓ icon/Lumen.icns"
