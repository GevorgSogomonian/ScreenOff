#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
xcrun swiftc -swift-version 5 -D POPOVER_TEST -module-cache-path .build/module-cache \
    Sources/ScreenOffCore/*.swift Sources/ScreenOff/*.swift Tests/PopoverIntegration.swift \
    -o .build/popover-integration
.build/popover-integration
