#!/bin/bash

# VoiceInk Build and Run Script

set -e

PROJECT_DIR="/Users/boemare/Documents/1.Projects/voice"
APP_NAME="VoiceInk.app"
DEST="/Applications/$APP_NAME"

echo "==> Killing any running VoiceInk instances..."
pkill -f VoiceInk 2>/dev/null || true
sleep 1

echo "==> Building VoiceInk..."
cd "$PROJECT_DIR"
xcodebuild -project VoiceInk.xcodeproj \
    -scheme VoiceInk \
    -configuration Debug \
    -destination 'platform=macOS' \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "==> Build failed!"
    exit 1
fi

BUILD_PATH=$(find ~/Library/Developer/Xcode/DerivedData -path "*/VoiceInk-*/Build/Products/Debug/VoiceInk.app" -not -path "*/Index.noindex/*" 2>/dev/null | head -1)

if [ -z "$BUILD_PATH" ]; then
    echo "==> Could not find built app!"
    exit 1
fi

echo "==> Removing old VoiceInk from Applications..."
rm -rf "$DEST"

echo "==> Copying new build to Applications..."
cp -R "$BUILD_PATH" "$DEST"

echo "==> Launching VoiceInk..."
open "$DEST"

echo "==> Done!"
