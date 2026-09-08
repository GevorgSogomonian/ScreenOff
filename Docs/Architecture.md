# Architecture

ScreenOff is a macOS accessory application with one reusable settings window. It creates no status item or Dock item. There is no package dependency, network client, system extension, privileged service, or telemetry.

## Components

- `DisplayHardware`: dynamically resolves SkyLight symbols; enumerates online and software-disabled displays, reads lid state, performs nonpersistent display transactions, and exposes recovery.
- `DisplayPolicy`: pure state machine. Automatic mode and a temporary manual override determine desired built-in state. A changed external UUID set clears overrides. Built-in topology changes alone do not. A failure inhibits further automatic attempts until explicit user action or an external topology change.
- `DisplayController`: main-actor serialization, SwiftUI state, display callbacks plus a two-second polling fallback, sleep/wake handling, verified transactions, and login registration. It starts a rescue process before every disable. Recovery responsibility survives missing panels, sleep, lid closure and failed transactions. An already-disabled panel discovered on launch is adopted for recovery. The helper is released only after the built-in is online and active with an open lid.
- `RecoveryGuard`: launches the bundled helper using anonymous pipes. It requires a READY response before any off transaction, then sends a heartbeat once per second from the main run loop.
- `ScreenOffWatchdog`: a separate process with its own WindowServer connection and AppKit event loop. It checks every 750 ms and watches pipe input asynchronously. EOF, an explicit restore command, parent death, 8 seconds without a heartbeat, lid closure, removal/disable callbacks for a protected external, or loss of the original external UUIDs requests recovery. `WatchdogRecovery` retries indefinitely, yielding between attempts, and exits only after two observations of an online, active built-in with an open lid. It only enables screens. No permanent launch agent is installed.

The pipe protocol uses byte 1 for heartbeat and byte 2 for restoration; `--restore`
starts a replacement helper directly in recovery mode. A restored panel does not
receive a redundant enable transaction. EOF cancels the read source, while the
timer continues recovery. A retired helper is allowed to finish before another
disable can start, preventing competing enable/disable transactions.
- `SettingsView` / `AppDelegate`: one positive preference switch, live status, and a quit button in a reusable settings window. The status item, popover and visibility preference implementation have been removed. The obsolete `hideStatusItem` value in existing preferences is ignored. `LSUIElement` and the accessory activation policy keep the app out of the Dock, including while settings is open. The window cannot be minimized into the Dock.
- LaunchServices reopen events (Spotlight/Finder) display the settings window. Closing this window does not stop display control. An explicit foreground launch opens settings; a login-item launch (the Apple event login marker) or `--background` remains quiet. A second process forwards a distributed show-settings notification to the existing instance and exits.
- The UI preference is the inverse of the existing `automaticDisplayOff` key: ON means both displays, OFF means automatic disabling. Existing installations need no preference migration. `setAutomatic` clears temporary recovery overrides; it remains an internal controller operation. Preview instances cannot evaluate display changes or register login items.

The hosting controller explicitly publishes its preferred content size. The
settings window fits its content, including multiline recovery or login notices.
It is centered on reopening and constrained to the current screen when resized.

## Recovery scheduling and energy

`SessionResumeState` separates screen locking/session inactivity, display sleep, and system sleep. An observed inactive-to-active cycle creates one request to reapply the saved display preference after a two-second settling interval. The controller consumes it only after recovery is confirmed, an external is usable, and the old helper has exited. Short lock cycles that leave the panel off consume their request without an extra transaction. Duplicate notifications cannot clear failure inhibition repeatedly. Explicit recovery/manual-on holds retain priority.

Lock/unlock uses the distributed `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked` notifications; workspace display sleep/wake and session switching are observed separately on `NSWorkspace.notificationCenter`. The existing two-second evaluation also reads `CGSessionCopyCurrentDictionary` as a missed-event fallback, using the on-console flag and the runtime `CGSSessionScreenIsLocked` key. No additional polling timer is introduced. The lock notification names/key are undocumented system details; their current operation is checked on the target Mac. See [Apple's screen-wake notification](https://developer.apple.com/documentation/appkit/nsworkspace/screensdidwakenotification) and the notification registrations in [Hammerspoon](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/caffeinate/libcaffeinate_watcher.m).

`RecoveryAttemptGate` is shared by the controller and helper. A closed lid permits one best-effort enable per process to clear the software disable; each then retains its obligation and observes the lid without further transactions. Opening the lid rearms immediately, including when no system sleep/wake event occurred. With an open lid, retries of an unchanged topology are separated by at least two seconds. A changed snapshot bypasses this cooldown for prompt recovery. The gate uses monotonic uptime and repeated recovery requests do not reset it.

Failed recovery transactions previously entered the same immediate rollback path as a failed disable. Their WindowServer callbacks could trigger further recovery evaluations with no cooldown, creating a transaction/callback loop. Recovery now records the attempt before calling the API; error handling cannot duplicate it. If the lid closes during verification, polling stops and the obligation persists. A failed disable still gets an immediate rollback attempt.

Unchanged snapshots/notices are not published to SwiftUI. Closed-lid waiting has no progress animation. Settings sizing is coalesced, skipped for closed windows, and applied only when dimensions actually differ. Timers allow coalescing (0.5 s controller, 0.2 s heartbeat, 0.1 s helper); their existing safety cadence is retained.

## Display transaction

1. Enumerate all displays again, including offline entries, and prefer the current `CGDisplayIsBuiltin` flag. Remember a positively identified built-in ID in memory. If unplugging removes the panel entirely, `BuiltInRecoveryTarget` permits an enable-only fallback to that ID with an open lid and no usable external. Refuse a cached ID assigned to any other current record. Never use the fallback for disabling.
2. Before disabling, check open lid, active external, and absence of mirroring.
3. Begin configuration; dynamically call `SLSConfigureDisplayEnabled` (fallback `CGSConfigureDisplayEnabled`); cancel on configuration failure.
4. Commit `forAppOnly` when disabling and `forSession` when restoring. Do not change brightness, gamma, resolutions, mirror relationships, or the external display's enabled flag.
5. Poll the fresh topology for up to 1.8 seconds. Never report an off state from the function return code alone. If an external disappears mid-transaction, request recovery.
6. On error, inhibit repeat attempts and undo the operation. Keep the rescue helper available if verification of restoration fails.

Recovery uses `forSession` so its enabled setting survives the recovering process's own exit. Neither executable ever commits with `permanently`. Restoration is not delayed by the debounce or an outstanding sleep flag. Once requested, it takes priority even if an external reconnects during recovery. Automatic disabling stays inhibited until an external topology change, an explicit user choice, or the single confirmed session-resume opportunity described above.

## Limitations

WindowServer's online/active state is evidence of a usable display link, not proof that a human can see that monitor. A monitor on another input or some docks may continue reporting an active link. The app cannot detect that reliably. Entries without vendor/model identity and the observed headless placeholder (vendor `0x756E6B6E`, model `0x76697274`, ASCII `unkn`/`virt`) cannot authorize disabling. Newly created placeholders cannot replace the helper's protected external UUIDs. Other virtual displays that present hardware identity may still count as externals.

Private ABI changes cannot be completely detected by symbol lookup. Verified online/offline status demonstrates a disconnect, not an electrical power measurement of the panel. The intended supported hardware is Apple Silicon MacBooks. macOS still controls physical closed-lid power behavior; ScreenOff clears its software disable and retains recovery responsibility until the lid is open and the panel is active.

## CLI

`--diagnose` is read-only and emits OS version, symbol availability, and topology JSON. `--recover` tells an existing instance to suspend automation and also invokes independent recovery. `--hardware-test` exercises the guarded display transaction for two seconds and restores it. CLI modes do not change the saved automatic preference.

`--restore-on-launch` starts the application with a temporary manual-on choice while preserving the automatic preference. It is useful after an update or a recovery. The saved switch position remains unchanged; choosing a mode again clears this temporary override. `--background` suppresses the initial settings window without affecting subsequent Spotlight reopen events.
