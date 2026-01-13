#!/bin/bash
# Build, install to /Applications, and run VoiceInk

set -e

echo "Killing existing VoiceInk..."
pkill -x VoiceInk 2>/dev/null || true

echo "Building..."
xcodebuild -scheme VoiceInk -configuration Debug -destination 'platform=macOS' build 2>&1 | grep -E "(error:|warning:|BUILD|Compiling)" || true

echo "Copying to /Applications..."
rm -rf /Applications/VoiceInk.app
cp -R ~/Library/Developer/Xcode/DerivedData/VoiceInk-efcgmsnpliraymgbblhfkpyiaryf/Build/Products/Debug/VoiceInk.app /Applications/

echo "Launching..."
open /Applications/VoiceInk.app

echo "Done!"
