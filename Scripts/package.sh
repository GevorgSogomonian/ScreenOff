#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

bash Scripts/build.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
NAME="ScreenOff-$VERSION-${ARCH:-arm64}"
mkdir -p .build/dmg
ditto dist/ScreenOff.app .build/dmg/ScreenOff.app
cp Resources/Installation-ru.txt .build/dmg/"Прочитайте перед установкой.txt"
if [[ ! -e .build/dmg/Applications ]]; then ln -s /Applications .build/dmg/Applications; fi
hdiutil create -volname "ScreenOff" -srcfolder .build/dmg -ov -format UDZO "dist/$NAME.dmg"
ditto -c -k --sequesterRsrc --keepParent dist/ScreenOff.app "dist/$NAME.zip"
shasum -a 256 "dist/$NAME.dmg" "dist/$NAME.zip" > dist/SHA256SUMS.txt
echo "Ready: dist/$NAME.dmg"
