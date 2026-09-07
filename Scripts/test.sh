#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
xcrun swiftc -swift-version 5 -module-cache-path .build/module-cache \
    Sources/ScreenOffCore/DisplayPolicy.swift Sources/ScreenOffCore/WatchdogRules.swift \
    Tests/PolicyTests.swift -o .build/policy-tests
.build/policy-tests
