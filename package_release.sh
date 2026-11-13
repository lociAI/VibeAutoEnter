#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$DIR/build"
DIST_DIR="$DIR/dist"
APP_NAME="VibeAutoEnter"
VERSION="1.2"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "=============================================="
echo " Packaging $APP_NAME v$VERSION for Marketplace"
echo "=============================================="

# 1. Compile and build the Universal App
"$DIR/build_app.sh"

# 2. Prepare Dist folder
mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR/$DMG_NAME"

echo "Creating DMG staging area..."
DMG_STAGING="$BUILD_DIR/dmg_staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

# Copy App bundle
cp -R "$APP_BUNDLE" "$DMG_STAGING/"

# Create /Applications symlink for drag-and-drop install
ln -s /Applications "$DMG_STAGING/Applications"

echo "Building disk image: $DIST_DIR/$DMG_NAME..."
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DIST_DIR/$DMG_NAME"

# Clean staging
rm -rf "$DMG_STAGING"

# Compute SHA256
echo "Generating SHA256 checksum..."
cd "$DIST_DIR"
shasum -a 256 "$DMG_NAME" > "${DMG_NAME}.sha256"

echo "=============================================="
echo " Release Package Ready!"
echo " DMG:      $DIST_DIR/$DMG_NAME"
echo " Checksum: $(cat "${DMG_NAME}.sha256")"
echo "=============================================="
