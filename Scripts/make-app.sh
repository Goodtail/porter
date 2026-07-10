#!/bin/sh
# Builds a distributable Porter.app bundle (release, ad-hoc signed) in dist/.
set -eu
cd "$(dirname "$0")/.."

VERSION="0.1.0"
swift build -c release

APP="dist/Porter.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Porter "$APP/Contents/MacOS/Porter"
# SPM resource bundle: Bundle.module also searches the main bundle's
# Resources directory — the right home for it inside an .app.
if [ -d .build/release/Porter_Porter.bundle ]; then
  cp -R .build/release/Porter_Porter.bundle "$APP/Contents/Resources/"
fi
cp Assets/PorterIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Porter</string>
    <key>CFBundleDisplayName</key>       <string>Porter</string>
    <key>CFBundleIdentifier</key>        <string>dev.porter.Porter</string>
    <key>CFBundleExecutable</key>        <string>Porter</string>
    <key>CFBundleIconFile</key>          <string>PorterIcon</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key>           <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>NSPrincipalClass</key>          <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>   <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "built $APP (v${VERSION}, ad-hoc signed)"
