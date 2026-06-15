#!/bin/bash
# One-command release: build → sign (Developer ID) → .dmg → notarize → staple.
#
# Fully non-interactive once two things live in the login keychain (set up once,
# reused by every future run and every agent on this machine — see docs/RELEASE.md):
#   1. the "Developer ID Application" certificate (already present)
#   2. a notarytool keychain profile (default name: affitor-notary)
#
# Usage: ./scripts/release.sh [version]   e.g. ./scripts/release.sh 0.1.0
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TEAM="${LUMEN_TEAM:-448LBGWBYM}"
SIGN_ID="${LUMEN_SIGN_IDENTITY:-Developer ID Application: Affitor LLC ($TEAM)}"
PROFILE="${LUMEN_NOTARY_PROFILE:-affitor-notary}"
VERSION="${1:-0.1.0}"
DMG="dist/Lumen.dmg"

echo "▶ build + sign for distribution"
echo "  identity: $SIGN_ID"
LUMEN_SIGN_IDENTITY="$SIGN_ID" ./scripts/build-app.sh release

echo "▶ package .dmg"
./scripts/make-dmg.sh
codesign --force --sign "$SIGN_ID" "$DMG"

# Notarize only if the keychain profile is set up; otherwise leave a signed
# (but not notarized) DMG and print the one-time setup pointer.
if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "▶ notarize (keychain profile: $PROFILE) — this calls Apple and waits"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  echo "▶ staple"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG" && echo "✓ notarized + stapled"
  echo ""
  echo "✓ $DMG is ready to ship. Attach it to a GitHub release:"
  echo "  gh release create v$VERSION \"$DMG\" --title \"Lumen v$VERSION\" --generate-notes"
else
  echo ""
  echo "⚠ Notary profile '$PROFILE' not found — DMG is signed but NOT notarized."
  echo "  One-time setup (see docs/RELEASE.md):"
  echo "    xcrun notarytool store-credentials \"$PROFILE\" \\"
  echo "      --key AuthKey_XXXX.p8 --key-id <KEY_ID> --issuer <ISSUER_ID>"
  echo "  Then re-run: ./scripts/release.sh $VERSION"
fi
echo "✓ $DMG"
