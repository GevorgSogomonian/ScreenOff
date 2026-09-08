#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$PWD/dist/ScreenOff.app"
BUILD="$PWD/.build"
ARCH="${ARCH:-arm64}"
IDENTITY="${SIGNING_IDENTITY:--}"
# Build a fresh bundle so files removed or renamed in an update cannot leak
# into the next release, including obsolete language-specific resources.
rm -rf "$APP"
mkdir -p "$BUILD/module-cache" "$APP/Contents/MacOS" "$APP/Contents/Resources"

COMMON=(-swift-version 5 -O -target "$ARCH-apple-macos13.0" -module-cache-path "$BUILD/module-cache")
xcrun swiftc "${COMMON[@]}" Sources/ScreenOffCore/*.swift Sources/ScreenOff/*.swift -o "$APP/Contents/MacOS/ScreenOff"
xcrun swiftc "${COMMON[@]}" Sources/ScreenOffCore/*.swift Sources/ScreenOffWatchdog/main.swift -o "$APP/Contents/MacOS/ScreenOffWatchdog"
xcrun swiftc -module-cache-path "$BUILD/module-cache" Scripts/MakeIcon.swift -o "$BUILD/make-icon"
"$BUILD/make-icon" "$BUILD/AppIcon.iconset"
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
cp Resources/Installation.txt "$APP/Contents/Resources/Installation.txt"

SIGN=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" != "-" ]]; then SIGN+=(--options runtime --timestamp); fi
codesign "${SIGN[@]}" "$APP/Contents/MacOS/ScreenOffWatchdog"
codesign "${SIGN[@]}" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
plutil -lint "$APP/Contents/Info.plist"
echo "Built: $APP ($ARCH)"
