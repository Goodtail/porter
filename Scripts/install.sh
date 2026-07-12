#!/bin/sh
# Porter installer — fetches the latest GitHub release DMG and installs
# /Applications/Porter.app.
#
#   curl -fsSL https://raw.githubusercontent.com/blick9/porter/main/Scripts/install.sh | sh
set -eu

REPO="blick9/porter"
DMG_URL=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" |
  grep -o '"browser_download_url": *"[^"]*\.dmg"' | head -1 | cut -d'"' -f4)
[ -n "$DMG_URL" ] || { echo "error: no DMG asset in the latest release" >&2; exit 1; }

TMP=$(mktemp -d)
MOUNT="$TMP/mnt"
cleanup() {
  hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

echo "downloading ${DMG_URL##*/} …"
curl -fL --progress-bar "$DMG_URL" -o "$TMP/Porter.dmg"
hdiutil attach "$TMP/Porter.dmg" -nobrowse -readonly -mountpoint "$MOUNT" -quiet

if [ -d /Applications/Porter.app ]; then
  echo "replacing existing /Applications/Porter.app"
  rm -rf /Applications/Porter.app
fi
ditto "$MOUNT/Porter.app" /Applications/Porter.app

# Pre-1.0 builds aren't notarized; clear quarantine so Gatekeeper lets it run.
xattr -dr com.apple.quarantine /Applications/Porter.app 2>/dev/null || true

echo ""
echo "installed /Applications/Porter.app — launch it with:"
echo "  open /Applications/Porter.app"
