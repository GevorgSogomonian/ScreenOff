# Verification

## Automated checks

`bash Scripts/test.sh` now runs 295 checks: 54 policy/lease checks, 19 popover geometry checks, and 222 checks of the production controller, recovery target selection and persistent watchdog recovery engine with injected hardware. The latter cannot issue real display transactions.

`bash Scripts/build.sh` compiles both executables, produces the icon and app bundle, verifies the code signature with `codesign --verify --deep --strict`, and lints Info.plist.

## Version 1.1.0: one preference and an optional status item

- Nine additional controller checks pass with injected hardware: migration of the old automatic preference to the inverse UI value, selecting OFF without an external, applying it after attachment, immediate restoration on ON, persistence of ON across topology changes, clearing a temporary recovery override, and preview controls never starting display transactions or helpers.
- `bash Scripts/test-interface.sh` passed 11 native checks in an isolated preview app bundle. They cover saved visibility, hidden background startup, a real LaunchServices reopen to the same PID, opening settings without returning the icon, fitting the content, closing/reusing the window, returning the icon, opening its popover, and hiding from the open popover. The latter caught an AppKit animated-close issue: the popover now closes synchronously before its status-item anchor is removed.
- The native menu was rendered and visually inspected: one display-preference switch, one hide/show button, status, Spotlight instructions and quit. The native settings-window bounds were checked against the complete content size. SwiftUI did not expose its child accessibility tree to the in-process test on this OS, so control count is verified visually rather than claimed as an automated accessibility check.
- All four native popover positioning checks passed with a 2.0-point gap on this Mac.
- The hardware transaction and watchdog recovery implementation from 1.0.3 is unchanged. The new UI tests never issue physical display transactions. The prior user-confirmed cable-removal result remains the hardware evidence; this UI release does not claim a new physical unplug, sleep or login test.

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

At the time of the 1.0.2 release, physical cable removal, lid closure and sleep had not been repeated. The subsequent physical unplug test still failed, leading to the hardware investigation and correction below. The simulated regressions alone had not established end-to-end hotplug recovery.

## Version 1.0.3: recorded hardware failure and working recovery

Physical unplug was reproduced with the user on this M1 Mac, with the built-in switch off and automatic mode on. Both a live AppKit observer and independent fresh diagnostic processes recorded the same result:

1. Before unplugging: built-in ID 1 was offline; external ID 2 was online/active.
2. After unplugging: ID 1 disappeared from the **private** `SLSGetDisplayList` as well. WindowServer created an active headless placeholder with vendor 1970170734/model 1986622068 (`unkn`/`virt`). An offline alias ID 3 remained, without the built-in flag.
3. Version 1.0.2 retained its recovery obligation, but could never resolve the missing built-in target. Repeating enumeration alone could not fix this. The public `CGRestorePermanentDisplayConfiguration()` was also tested and did not restore the panel; it is not part of the fix.
4. A restore-only diagnostic enabled the last positively identified built-in ID 1, even though it was absent from the current private list. Begin/configure/commit all returned success. ID 1 returned online/active before the external was reconnected. The user confirmed seeing the built-in screen turn on.

The production fix remembers only a positively identified built-in ID in memory. A current built-in ID always wins. The remembered-ID fallback can only enable, with the lid open, no usable external, and no other current record assigned that ID. The observed virtual placeholder is excluded from usable externals. Regression tests replay the recorded topology through the real controller and watchdog recovery engine, and reject reuse for disabling, a closed lid, another physical external, conflicting IDs, and missing identity history.

**Final application validation passed:** ScreenOff 1.0.3 was installed in `/Applications` and started with `--restore-on-launch`. All temporary diagnostic/recovery processes were stopped. The user then disabled the built-in with the first switch, left automatic mode enabled, and physically removed the cable. The user confirmed that the built-in turned on in the actual application. This is end-to-end confirmation of the reported scenario on this Mac/dock. Sleep, closed-lid sequences, other Macs and other docks remain separate manual checks.

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
- Turn the single preference ON; the built-in must restore and stay on across external reconnections. Turn it OFF again to resume automatic disabling.
- Sleep and wake with an external attached; recovery must complete first and the screen must remain available until reconnecting the external or choosing the OFF preference again.
- Close/open the lid; the pending restoration must survive and complete once the panel becomes active.
- Quit while off; the built-in must return and the helper must exit.
- Remove external during a transition; the built-in must recover.
- Restart macOS with the preference OFF and login approval granted; ScreenOff must start without opening settings. The hidden-icon preference must remain in effect.
- Hide the icon, close settings, then open ScreenOff through Spotlight; settings must reappear without a second process or an unwanted status item.
- Try a mirrored layout; the app must leave it unchanged and explain the prerequisite.

These physical hotplug, sleep and login scenarios require manual hardware interaction; unit checks alone do not establish them.
