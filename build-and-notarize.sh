#!/bin/bash
set -e

# Configuration
APP_NAME="Geodo"
SIGNING_IDENTITY="Developer ID Application: Geome Ltd (RC2653C4DY)"
NOTARYTOOL_PROFILE="notarytool-profile"

# Paths
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_PATH="$BUILD_DIR/Release/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"

echo "🧹 Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/Release"

echo "🔨 Building app with automatic signing..."
xcodebuild -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    build

# Find the built app
BUILT_APP=$(find "$BUILD_DIR/DerivedData" -name "$APP_NAME.app" -type d | head -1)
echo "📁 Found built app at: $BUILT_APP"
cp -R "$BUILT_APP" "$APP_PATH"

# Create entitlements without keychain-access-groups for Developer ID
cat > "$BUILD_DIR/DevID.entitlements" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.screen-capture</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-only</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
</dict>
</plist>
EOF

echo "🔐 Re-signing with Developer ID..."

# Sign everything inside-out to maintain code signature validity
# The order matters: deepest nested items first, then their parents

FRAMEWORKS_DIR="$APP_PATH/Contents/Frameworks"

# 1. Sign Sparkle's deeply nested components first
echo "  Signing Sparkle nested components..."

# Sign XPC services inside Sparkle
for xpc in "$FRAMEWORKS_DIR/Sparkle.framework/Versions/B/XPCServices"/*.xpc; do
    if [ -d "$xpc" ]; then
        echo "    Signing $(basename "$xpc")..."
        codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$xpc"
    fi
done

# Sign Autoupdate binary
if [ -f "$FRAMEWORKS_DIR/Sparkle.framework/Versions/B/Autoupdate" ]; then
    echo "    Signing Autoupdate..."
    codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$FRAMEWORKS_DIR/Sparkle.framework/Versions/B/Autoupdate"
fi

# Sign Updater.app inside Sparkle
if [ -d "$FRAMEWORKS_DIR/Sparkle.framework/Versions/B/Updater.app" ]; then
    echo "    Signing Updater.app..."
    codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$FRAMEWORKS_DIR/Sparkle.framework/Versions/B/Updater.app"
fi

# 2. Now sign the frameworks themselves
echo "  Signing frameworks..."
for framework in "$FRAMEWORKS_DIR"/*.framework; do
    if [ -d "$framework" ]; then
        echo "    Signing $(basename "$framework")..."
        codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$framework"
    fi
done

# 3. Sign any dylibs
for dylib in "$FRAMEWORKS_DIR"/*.dylib; do
    if [ -f "$dylib" ]; then
        echo "    Signing $(basename "$dylib")..."
        codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$dylib"
    fi
done

# 4. Sign the main app last
echo "  Signing main app..."
codesign --force --options runtime --sign "$SIGNING_IDENTITY" --entitlements "$BUILD_DIR/DevID.entitlements" "$APP_PATH"

echo "✅ Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "📤 Creating ZIP for notarization..."
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "🍎 Submitting for notarization (this may take a few minutes)..."
xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait

echo "📎 Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"

echo "💿 Creating DMG..."
DMG_TEMP="$BUILD_DIR/dmg-temp"
mkdir -p "$DMG_TEMP"
cp -R "$APP_PATH" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$DMG_PATH"

echo "🍎 Notarizing DMG..."
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait

echo "📎 Stapling DMG..."
xcrun stapler staple "$DMG_PATH"

# Cleanup
rm -rf "$DMG_TEMP" "$ZIP_PATH" "$BUILD_DIR/DevID.entitlements"

echo ""
echo "✅ Done! Your notarized DMG is at:"
echo "   $DMG_PATH"
