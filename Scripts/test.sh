#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
xcrun swiftc -swift-version 5 -module-cache-path .build/module-cache \
    Sources/ScreenOffCore/DisplayPolicy.swift Sources/ScreenOffCore/WatchdogRules.swift \
    Tests/PolicyTests.swift -o .build/policy-tests
.build/policy-tests
xcrun swiftc -swift-version 5 -D CONTROLLER_TEST -module-cache-path .build/module-cache \
    Sources/ScreenOffCore/*.swift Sources/ScreenOff/RecoveryGuard.swift \
    Sources/ScreenOff/DisplayController.swift Tests/RecoveryControllerTests.swift \
    -o .build/recovery-tests
.build/recovery-tests
