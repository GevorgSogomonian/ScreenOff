#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/.build/ScreenOffInterfaceTests.app"
FIXTURE="$PWD/.build/ScreenOffFocusFixture.app"
mkdir -p .build/module-cache "$APP/Contents/MacOS" "$FIXTURE/Contents/MacOS"
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path .build/module-cache \
    Tests/FocusFixture.swift -o "$FIXTURE/Contents/MacOS/ScreenOffFocusFixture"
cat > "$FIXTURE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.gevorg.screenoff.focus-fixture</string>
<key>CFBundleName</key><string>ScreenOff Focus Fixture</string>
<key>CFBundleExecutable</key><string>ScreenOffFocusFixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$FIXTURE"
# Only the isolated fixture is terminated if the test fails before cleanup.
trap 'pkill -f "^$FIXTURE/Contents/MacOS/ScreenOffFocusFixture$" 2>/dev/null || true' EXIT
xcrun swiftc -swift-version 5 -D INTERFACE_TEST -module-cache-path .build/module-cache \
    Sources/ScreenOffCore/*.swift Sources/ScreenOff/*.swift Tests/InterfaceIntegration.swift \
    -o "$APP/Contents/MacOS/ScreenOffInterfaceTests"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.gevorg.screenoff.interface-tests</string>
<key>CFBundleName</key><string>ScreenOff Interface Tests</string>
<key>CFBundleExecutable</key><string>ScreenOffInterfaceTests</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>LSMultipleInstancesProhibited</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/ScreenOffInterfaceTests"
