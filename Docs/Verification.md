# Verification

## Automated checks

`bash Scripts/test.sh` now runs 266 checks: 54 policy/lease checks, 19 popover geometry checks, and 193 checks of the production controller and persistent watchdog recovery engine with injected hardware. The latter cannot issue real display transactions.

`bash Scripts/build.sh` compiles both executables, produces the icon and app bundle, verifies the code signature with `codesign --verify --deep --strict`, and lints Info.plist.

## Version 1.0.1: menu positioning

- 19 additional geometry checks pass for growing/shrinking menu content, display edges, and monitors above, below, left and right of the primary screen.
- `bash Scripts/test-popover.sh` uses the actual AppDelegate/NSPopover in preview mode. All four stages passed on this Mac: initial presentation, content growth, content shrink, and reopening. Each measured a 2.0-point gap between the status button and the top of the native popover window.
- Preview mode does not start or evaluate the display controller and does not change preferences. The test menu stays open across focus changes so activity in another app cannot interrupt the frame measurements; production retains normal transient-menu behavior.
- All 54 original policy/watchdog checks continue to pass (73 pure checks total). The display switching implementation is unchanged in this patch.

## Version 1.0.2: unplug and lid recovery

The user reported that removing the monitor cable from the Mac or dock left the built-in disabled, even after closing/opening the lid. Code inspection found premature release when the built-in disappeared from enumeration, unverified release before sleep, a lid-closed false success, and a helper that exited after bounded unsuccessful recovery. These paths now retain the restoration obligation.

- The production `DisplayController` is tested against temporary loss of both displays, repeated API/read failures, changed built-in IDs, inactive-but-online panels, sleep without a wake callback, lid closure, helper death, orphaned disabled panels on startup, stale active lists after remove/disable events, temporary headless displays, unplug during the off transaction, and reconnection during recovery.
- The production `WatchdogRecovery` is tested across 100 unavailable-panel polls, lid closure, repeated API errors, transient loss during verification, and already-restored panels. It must not finish until two separate observations confirm an online/active built-in with an open lid. A redundant enable is not required for a panel already confirmed active.
- `bash Scripts/test-restore-only.sh` passed against the actual 1.0.2 helper for explicit restore command, pipe EOF while the parent remains alive, and `--restore` startup. Each helper exited successfully and the built-in was confirmed active. No disable command was sent. This validates IPC and completion, not physical hotplug recovery.
- `bash Scripts/test-popover.sh` passed all four native AppKit stages again. The measured gap was 2.5 points for initial show, growth, shrink and reopen with the current display configuration.
- Before developing this fix, `--recover` successfully restored the user's disabled panel; a separate read-only diagnostic confirmed it online and active. Development and validation of 1.0.2 did not deliberately disable it again.

**Physical cable removal, lid closure and sleep have not been repeated with 1.0.2.** The simulated regressions establish the corrected control flow, but final end-to-end confirmation of the reported cable-removal scenario requires testing the updated app on the user's Mac/dock.

## Earlier hardware validation (1.0.0)

Target: MacBook Pro (M1), macOS 27.0 beta, build 26A5425a. Read-only probing found both SLS/CGS disconnect and display-list symbols, an online built-in panel, and one active external display.

Passed on this Mac:

- The real guarded transaction disabled the built-in panel, removed it from the online display list and left the external display active.
- The panel remained disabled for two seconds, then returned online through the same transaction path used by the menu switch.
- The independent helper restored the built-in panel after its heartbeat pipe was closed while the parent process stayed alive. This verifies actual recovery from a second process, not merely WindowServer's automatic cleanup after the controlling process exits.
- The menu's accessibility tree exposed two switches and the quit button. The native view was rendered and visually checked; the documented preview is in `Menu.png`.
- Both application binaries were compiled for arm64 with a macOS 13 deployment target; ad-hoc signatures and Info.plist validation passed.
- The packaged DMG passed `hdiutil verify`; its ZIP passed `unzip -tq`. A final repeat of the live probe was refused after the laptop lid was closed, as required by the safety guard; the earlier successful open-lid hardware tests are the basis of the switching result above.

The integration harness runs a full `NSApplication` event loop. A plain synchronous loop can retain stale CoreGraphics state after a different process changes display configuration and falsely report that a successful recovery failed. The helper also maintains a proper application event loop. Anonymous pipe handles use close-on-exec for parent-only ends.

## Manual regression checklist

- Unplug the last external while built-in is off; the built-in must return.
- Reconnect with automatic mode enabled; the built-in must turn off after settling.
- Turn built-in on manually while automatic remains enabled; it must stay on until external topology changes.
- Sleep and wake with an external attached; recovery must complete first and the screen must remain available until reconnecting the external or choosing off manually.
- Close/open the lid; the pending restoration must survive and complete once the panel becomes active.
- Quit while off; the built-in must return and the helper must exit.
- Remove external during a transition; the built-in must recover.
- Restart macOS with automatic mode enabled and login approval granted; ScreenOff must start.
- Try a mirrored layout; the app must leave it unchanged and explain the prerequisite.

These physical hotplug, sleep and login scenarios require manual hardware interaction; unit checks alone do not establish them.
