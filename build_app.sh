#!/bin/bash
set -e

SRC_DIR="/Users/mac101/Developer/VibeAutoEnter/VibeAutoEnter"
BUILD_DIR="/Users/mac101/Developer/VibeAutoEnter/build"
APP_NAME="VibeAutoEnter"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "=== Building Universal (x86_64 + arm64) $APP_NAME ==="
mkdir -p "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo "Compiling for x86_64..."
swiftc -target x86_64-apple-macos14.0 \
    -O \
    "$SRC_DIR/AutoEnterMonitor.swift" \
    "$SRC_DIR/LicenseManager.swift" \
    "$SRC_DIR/LicenseSheetView.swift" \
    "$SRC_DIR/ContentView.swift" \
    "$SRC_DIR/VibeAutoEnterApp.swift" \
    -o "$BUILD_DIR/VibeAutoEnter_x86_64"

echo "Compiling for arm64..."
swiftc -target arm64-apple-macos14.0 \
    -O \
    "$SRC_DIR/AutoEnterMonitor.swift" \
    "$SRC_DIR/LicenseManager.swift" \
    "$SRC_DIR/LicenseSheetView.swift" \
    "$SRC_DIR/ContentView.swift" \
    "$SRC_DIR/VibeAutoEnterApp.swift" \
    -o "$BUILD_DIR/VibeAutoEnter_arm64"

echo "Creating Universal Binary..."
lipo -create -output "$APP_BUNDLE/Contents/MacOS/$APP_NAME" "$BUILD_DIR/VibeAutoEnter_x86_64" "$BUILD_DIR/VibeAutoEnter_arm64"
rm -f "$BUILD_DIR/VibeAutoEnter_x86_64" "$BUILD_DIR/VibeAutoEnter_arm64"

echo "Copying Info.plist..."
cp "$SRC_DIR/Info.plist" "$APP_BUNDLE/Contents/"
sed -i '' "s/\$(EXECUTABLE_NAME)/$APP_NAME/g" "$APP_BUNDLE/Contents/Info.plist"
sed -i '' "s/\$(PRODUCT_NAME)/$APP_NAME/g" "$APP_BUNDLE/Contents/Info.plist"
sed -i '' "s/\$(PRODUCT_BUNDLE_PACKAGE_TYPE)/APPL/g" "$APP_BUNDLE/Contents/Info.plist"
sed -i '' "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/com.vibetools.VibeAutoEnter/g" "$APP_BUNDLE/Contents/Info.plist"
sed -i '' "s/\$(MACOSX_DEPLOYMENT_TARGET)/14.0/g" "$APP_BUNDLE/Contents/Info.plist"

echo "Signing application bundle..."
codesign --force --deep --sign - --entitlements "$SRC_DIR/VibeAutoEnter.entitlements" "$APP_BUNDLE"

echo "Copying to ~/Applications..."
mkdir -p /Users/mac101/Applications
rm -rf "/Users/mac101/Applications/$APP_NAME.app"
cp -R "$APP_BUNDLE" /Users/mac101/Applications/

echo "=== Build Complete! ==="
echo "App created at: /Users/mac101/Applications/$APP_NAME.app"
