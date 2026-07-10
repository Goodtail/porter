#!/bin/sh
# Full direct-distribution release: notarized DMG → GitHub Release → Sparkle appcast.
#
#   1. Scripts/release-notarized.sh   signed + notarized + stapled DMG in dist/
#   2. generate_appcast               EdDSA-signs the update (private key from the
#                                     login Keychain) and writes appcast.xml
#   3. gh release create              uploads the DMG as a release asset
#   4. commit & push appcast.xml      the SUFeedURL apps poll on launch
#
# One-time setup (in addition to release-notarized.sh prereqs):
#   swift build                                            # fetches Sparkle tools
#   .build/artifacts/sparkle/Sparkle/bin/generate_keys     # keypair → login Keychain
#   export SPARKLE_ED_PUBLIC_KEY="<printed public key>"
#   gh auth login
#
# Usage:
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID1234)" \
#   SPARKLE_ED_PUBLIC_KEY="..." VERSION=1.0.0 BUILD_NUMBER=2 \
#   Scripts/release-github.sh
#
# Optional env: REPO (default blick9/porter), NOTARY_PROFILE, BUNDLE_ID
set -eu
cd "$(dirname "$0")/.."

: "${VERSION:?set VERSION, e.g. 1.0.0}"
: "${SPARKLE_ED_PUBLIC_KEY:?run generate_keys once and export the public key — updates cannot be verified without it}"
REPO="${REPO:-blick9/porter}"
export VERSION SPARKLE_ED_PUBLIC_KEY

command -v gh >/dev/null 2>&1 || { echo "gh CLI required (brew install gh)"; exit 1; }
TOOLS=".build/artifacts/sparkle/Sparkle/bin"
[ -x "$TOOLS/generate_appcast" ] || { echo "Sparkle tools missing — run 'swift build' first"; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "working tree not clean — commit or stash first"; exit 1; }

Scripts/release-notarized.sh
DMG="dist/Porter-${VERSION}.dmg"

# Appcast over a stage dir holding only this release: Sparkle only needs the
# newest entry, and generate_appcast pulls version info out of the DMG itself.
STAGE="dist/appcast-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp "$DMG" "$STAGE/"
"$TOOLS/generate_appcast" \
  --download-url-prefix "https://github.com/${REPO}/releases/download/v${VERSION}/" \
  -o appcast.xml "$STAGE"
rm -rf "$STAGE"

gh release create "v${VERSION}" "$DMG" \
  --repo "$REPO" --title "Porter ${VERSION}" --generate-notes

git add appcast.xml
git commit -m "release: v${VERSION} appcast"
git push origin main

echo ""
echo "released v${VERSION}:"
echo "  download  https://github.com/${REPO}/releases/tag/v${VERSION}"
echo "  appcast   pushed to main (SUFeedURL target) — installed apps will see the update"
