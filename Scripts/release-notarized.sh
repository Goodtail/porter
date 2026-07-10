#!/bin/sh
# Developer ID release: hardened-runtime signed, notarized, stapled DMG in dist/.
# This is the recommended distribution channel for Porter — the app's core
# features (process scan / kill / ssh) do not work under the App Sandbox,
# so direct distribution outside the Mac App Store keeps full functionality.
#
# One-time setup:
#   1. Join the Apple Developer Program.
#   2. Create a "Developer ID Application" certificate (Xcode → Settings →
#      Accounts → Manage Certificates, or developer.apple.com).
#   3. Store notarization credentials (app-specific password from appleid.apple.com):
#        xcrun notarytool store-credentials porter-notary \
#          --apple-id you@example.com --team-id TEAMID1234 --password app-specific-pw
#
# Usage:
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID1234)" \
#   BUNDLE_ID=com.yourdomain.porter VERSION=1.0.0 BUILD_NUMBER=1 \
#   Scripts/release-notarized.sh
#
# Optional env: NOTARY_PROFILE (default porter-notary)
set -eu
cd "$(dirname "$0")/.."

: "${DEVELOPER_ID:?set DEVELOPER_ID to your 'Developer ID Application: …' identity (see: security find-identity -v -p codesigning)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-porter-notary}"
VERSION="${VERSION:-0.1.0}"
export VERSION

if [ -z "${SPARKLE_ED_PUBLIC_KEY:-}" ]; then
  echo "warning: SPARKLE_ED_PUBLIC_KEY is not set — the shipped app cannot verify"
  echo "         auto-updates. Run .build/artifacts/sparkle/Sparkle/bin/generate_keys"
  echo "         once and export the printed public key."
fi

Scripts/make-app.sh
APP="dist/Porter.app"

# Re-sign with hardened runtime + secure timestamp (both required by
# notarization) — Sparkle's nested executables first, then framework, then app.
FW="$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$FW/Versions/B/XPCServices/Downloader.xpc"
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" --preserve-metadata=entitlements "$FW/Versions/B/XPCServices/Installer.xpc"
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$FW/Versions/B/Autoupdate"
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$FW/Versions/B/Updater.app"
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$FW"
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

# DMG with /Applications shortcut.
DMG="dist/Porter-${VERSION}.dmg"
STAGE="dist/dmg-root"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Porter" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"

# Notarize the DMG (covers the app inside), then staple the ticket.
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo ""
echo "done: $DMG (signed, notarized, stapled) — ready to distribute"
