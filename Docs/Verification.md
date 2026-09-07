# Verification

## Automated checks

`bash Scripts/test.sh` covers 54 assertions: automatic/manual priority, built-in self-events, monitor replacement and ordering, no-active-external invariants, mirroring, lid closure, missing panels, failure inhibition, crash, EOF, heartbeat timeout, and independent unplug recovery decisions.

`bash Scripts/build.sh` compiles both executables, produces the icon and app bundle, verifies the code signature with `codesign --verify --deep --strict`, and lints Info.plist.

## Hardware validation

Target: MacBook Pro (M1), macOS 27.0 beta, build 26A5425a. Read-only probing found both SLS/CGS disconnect and display-list symbols, an online built-in panel, and one active external display.

Passed on this Mac:

- The real guarded transaction disabled the built-in panel, removed it from the online display list and left the external display active.
- The panel remained disabled for two seconds, then returned online through the same transaction path used by the menu switch.
- The independent helper restored the built-in panel after its heartbeat pipe was closed while the parent process stayed alive. This verifies actual recovery from a second process, not merely WindowServer's automatic cleanup after the controlling process exits.
- The menu's accessibility tree exposed two switches and the quit button. The native view was rendered and visually checked; the documented preview is in `Menu.png`.
- Both application binaries were compiled for arm64 with a macOS 13 deployment target; ad-hoc signatures and Info.plist validation passed.

The integration harness runs a full `NSApplication` event loop. A plain synchronous loop can retain stale CoreGraphics state after a different process changes display configuration and falsely report that a successful recovery failed. The helper also maintains a proper application event loop. Anonymous pipe handles use close-on-exec for parent-only ends.

## Manual regression checklist

- Unplug the last external while built-in is off; the built-in must return.
- Reconnect with automatic mode enabled; the built-in must turn off after settling.
- Turn built-in on manually while automatic remains enabled; it must stay on until external topology changes.
- Sleep and wake with an external attached; the intended mode must resume once links settle.
- Close/open the lid; the app must not fight native clamshell behavior.
- Quit while off; the built-in must return and the helper must exit.
- Remove external during a transition; the built-in must recover.
- Restart macOS with automatic mode enabled and login approval granted; ScreenOff must start.
- Try a mirrored layout; the app must leave it unchanged and explain the prerequisite.

These physical hotplug, sleep and login scenarios require manual hardware interaction; unit checks alone do not establish them.
