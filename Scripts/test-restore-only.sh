#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
xcrun swiftc -swift-version 5 -module-cache-path .build/module-cache \
    Sources/ScreenOffCore/*.swift Tests/WatchdogRestoreOnly.swift -o .build/restore-only-tests
.build/restore-only-tests "$PWD/dist/ScreenOff.app/Contents/MacOS/ScreenOffWatchdog"
