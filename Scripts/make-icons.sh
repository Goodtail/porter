#!/bin/sh
# Regenerates all icon artifacts from Scripts/generate-icon.swift:
#   Assets/icon-1024.png              — master + README hero
#   Assets/PorterIcon.icns            — for the .app bundle
#   Sources/Porter/Resources/AppIcon.png — runtime Dock icon (swift run)
set -eu
cd "$(dirname "$0")/.."

mkdir -p Assets Sources/Porter/Resources
swift Scripts/generate-icon.swift Assets/icon-1024.png

ICONSET=$(mktemp -d)/Porter.iconset
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Assets/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d Assets/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Assets/PorterIcon.icns
rm -rf "$(dirname "$ICONSET")"

sips -z 512 512 Assets/icon-1024.png --out Sources/Porter/Resources/AppIcon.png >/dev/null
echo "icons regenerated"
