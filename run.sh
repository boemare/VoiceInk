#!/bin/bash
# Build, install to /Applications, and run Geodo

set -e

echo "Killing existing Geodo..."
pkill -x Geodo 2>/dev/null || true

echo "Building..."
xcodebuild -scheme Geodo -configuration Debug -destination 'platform=macOS' build 2>&1 | grep -E "(error:|warning:|BUILD|Compiling)" || true

echo "Copying to /Applications..."
rm -rf /Applications/Geodo.app
cp -R ~/Library/Developer/Xcode/DerivedData/Geodo-*/Build/Products/Debug/Geodo.app /Applications/

echo "Launching..."
open /Applications/Geodo.app

echo "Done!"
