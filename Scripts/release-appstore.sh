#!/bin/sh
# Mac App Store packaging: sandbox-entitled, Apple Distribution signed .pkg.
#
# ⚠️ READ docs/APP_STORE.md FIRST. Porter's local scan / kill / ssh features
#    do not work under the App Sandbox (mandatory on the MAS). This script
#    prepares the upload pipeline; shipping on the MAS additionally requires
#    re-architecting those features.
#
# One-time setup (developer.apple.com + App Store Connect):
#   1. Register the bundle ID and create the app record in App Store Connect.
#   2. Certificates: "Apple Distribution" and "Mac Installer Distribution".
#   3. Provisioning profile: type "Mac App Store", for the bundle ID.
#
# Usage:
#   APP_SIGN_IDENTITY="Apple Distribution: Your Name (TEAMID1234)" \
#   PKG_SIGN_IDENTITY="3rd Party Mac Developer Installer: Your Name (TEAMID1234)" \
#   PROVISIONING_PROFILE=path/to/Porter_MAS.provisionprofile \
#   BUNDLE_ID=com.yourdomain.porter VERSION=1.0.0 BUILD_NUMBER=1 \
#   Scripts/release-appstore.sh
set -eu
cd "$(dirname "$0")/.."

: "${APP_SIGN_IDENTITY:?set APP_SIGN_IDENTITY to your 'Apple Distribution: …' identity}"
: "${PKG_SIGN_IDENTITY:?set PKG_SIGN_IDENTITY to your 'Mac Installer Distribution / 3rd Party Mac Developer Installer: …' identity}"
: "${PROVISIONING_PROFILE:?set PROVISIONING_PROFILE to a Mac App Store .provisionprofile path}"
VERSION="${VERSION:-0.1.0}"
export VERSION

Scripts/make-app.sh
APP="dist/Porter.app"

# MAS bits: embedded provisioning profile + sandbox entitlements.
cp "$PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"
codesign --force --timestamp \
  --entitlements Packaging/PorterAppStore.entitlements \
  --sign "$APP_SIGN_IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"
codesign -d --entitlements - "$APP"

PKG="dist/Porter-${VERSION}.pkg"
rm -f "$PKG"
productbuild --component "$APP" /Applications --sign "$PKG_SIGN_IDENTITY" "$PKG"

echo ""
echo "done: $PKG"
echo "upload with the Transporter app (Mac App Store, free) or:"
echo "  xcrun iTMSTransporter -m upload -assetFile $PKG -u <apple-id> ..."
echo "then submit the build for review in App Store Connect."
