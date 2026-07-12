#!/bin/sh
# Builds a distributable Porter.app bundle (release) in dist/.
# Ad-hoc signed by default — release scripts re-sign for distribution.
#
# Env overrides:
#   VERSION               marketing version (CFBundleShortVersionString), default 0.1.0
#   BUILD_NUMBER          CFBundleVersion — must increase per release, default 1
#   BUNDLE_ID             CFBundleIdentifier, default com.goodtail.porter
#   SIGN_IDENTITY         codesign identity, default "-" (ad-hoc)
#   COPYRIGHT             NSHumanReadableCopyright
#   FEED_URL              Sparkle appcast URL (SUFeedURL)
#   SPARKLE_ED_PUBLIC_KEY Sparkle EdDSA public key (SUPublicEDKey; omitted if empty —
#                         updates won't verify without it, dev builds don't care)
set -eu
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUNDLE_ID="${BUNDLE_ID:-com.goodtail.porter}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
COPYRIGHT="${COPYRIGHT:-© 2026 Porter. MIT License.}"
FEED_URL="${FEED_URL:-https://raw.githubusercontent.com/Goodtail/porter/main/appcast.xml}"

swift build -c release

APP="dist/Porter.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp .build/release/Porter "$APP/Contents/MacOS/Porter"
# SPM resource bundle: Bundle.module also searches the main bundle's
# Resources directory — the right home for it inside an .app.
# Localized .strings tables (en/ko/ja) live inside this bundle.
if [ -d .build/release/Porter_Porter.bundle ]; then
  cp -R .build/release/Porter_Porter.bundle "$APP/Contents/Resources/"
fi
cp Assets/PorterIcon.icns "$APP/Contents/Resources/"

# Sparkle auto-update framework (binary reaches it via @executable_path/../Frameworks).
cp -R .build/release/Sparkle.framework "$APP/Contents/Frameworks/"

# .lproj stubs in the app bundle so macOS lists the app's languages
# (System Settings → General → Language & Region → Applications).
for lang in en ko ja; do
  mkdir -p "$APP/Contents/Resources/$lang.lproj"
done

SPARKLE_KEY_ENTRY=""
if [ -n "${SPARKLE_ED_PUBLIC_KEY:-}" ]; then
  SPARKLE_KEY_ENTRY="<key>SUPublicEDKey</key><string>${SPARKLE_ED_PUBLIC_KEY}</string>"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Porter</string>
    <key>CFBundleDisplayName</key>       <string>Porter</string>
    <key>CFBundleIdentifier</key>        <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>        <string>Porter</string>
    <key>CFBundleIconFile</key>          <string>PorterIcon</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key>           <string>${BUILD_NUMBER}</string>
    <key>CFBundleDevelopmentRegion</key> <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>ko</string>
        <string>ja</string>
    </array>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>LSApplicationCategoryType</key> <string>public.app-category.developer-tools</string>
    <key>NSPrincipalClass</key>          <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSHumanReadableCopyright</key>  <string>${COPYRIGHT}</string>
    <!-- Sparkle auto-update feed -->
    <key>SUFeedURL</key>                 <string>${FEED_URL}</string>
    ${SPARKLE_KEY_ENTRY}
    <!-- App Store Connect export compliance: Porter implements no encryption
         of its own (SSH is delegated to the system /usr/bin/ssh binary). -->
    <key>ITSAppUsesNonExemptEncryption</key> <false/>
    <!-- dev servers speak plain http (localhost, tailnet IPs) — favicon fetch needs this -->
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key> <true/>
    </dict>
</dict>
</plist>
PLIST

# Sign Sparkle's nested executables first, then the framework, then the app
# (same order the notarized release re-signs in).
FW="$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$SIGN_IDENTITY" "$FW/Versions/B/XPCServices/Downloader.xpc"
codesign --force --sign "$SIGN_IDENTITY" --preserve-metadata=entitlements "$FW/Versions/B/XPCServices/Installer.xpc"
codesign --force --sign "$SIGN_IDENTITY" "$FW/Versions/B/Autoupdate"
codesign --force --sign "$SIGN_IDENTITY" "$FW/Versions/B/Updater.app"
codesign --force --sign "$SIGN_IDENTITY" "$FW"
codesign --force --sign "$SIGN_IDENTITY" "$APP"
if [ "$SIGN_IDENTITY" = "-" ]; then
  echo "built $APP (v${VERSION} build ${BUILD_NUMBER}, ad-hoc signed)"
else
  echo "built $APP (v${VERSION} build ${BUILD_NUMBER}, signed: ${SIGN_IDENTITY})"
fi
