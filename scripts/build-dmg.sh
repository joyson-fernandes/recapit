#!/bin/bash
set -e
cd /Users/joyson/recapit
xcodebuild -project recapit.xcodeproj -scheme recapit -configuration Release \
  -derivedDataPath build ONLY_ACTIVE_ARCH=NO build
APP_PATH="build/Build/Products/Release/recapit.app"
DMG_NAME="recapit-1.0.0.dmg"
rm -f "$DMG_NAME"
hdiutil create -volname "Recapit" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_NAME"
echo "Done: $DMG_NAME"
