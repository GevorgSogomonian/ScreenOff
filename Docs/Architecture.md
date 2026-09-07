# Architecture

ScreenOff is a macOS accessory application. There is no Dock item, primary window, package dependency, network client, system extension, privileged service, or telemetry.

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
- `MenuView` / `AppDelegate`: two switches in a native popover, live status, quit button, single-instance handling.

The hosting controller explicitly publishes its preferred content size. After
presentation and every native window resize, the popover's top is anchored to
the status button converted into global screen coordinates. The native horizontal
placement is preserved so the arrow remains aligned. Screen-configuration changes
close the old popover, letting the next click acquire the current status-item
window and display scale. This avoids the vertical gap after status/login text
shrinks or the built-in screen is disconnected.

## Display transaction

1. Enumerate all displays again, including offline entries, and resolve the built-in by the current `CGDisplayIsBuiltin` flag.
2. Before disabling, check open lid, active external, and absence of mirroring.
3. Begin configuration; dynamically call `SLSConfigureDisplayEnabled` (fallback `CGSConfigureDisplayEnabled`); cancel on configuration failure.
4. Commit `forAppOnly` when disabling and `forSession` when restoring. Do not change brightness, gamma, resolutions, mirror relationships, or the external display's enabled flag.
5. Poll the fresh topology for up to 1.8 seconds. Never report an off state from the function return code alone. If an external disappears mid-transaction, request recovery.
6. On error, inhibit repeat attempts and undo the operation. Keep the rescue helper available if verification of restoration fails.

Recovery uses `forSession` so its enabled setting survives the recovering process's own exit. Neither executable ever commits with `permanently`. Restoration is not delayed by the debounce or an outstanding sleep flag. Once requested, it takes priority even if an external reconnects during recovery. Automatic disabling is inhibited until the next external topology change or an explicit user choice.

## Limitations

WindowServer's online/active state is evidence of a usable display link, not proof that a human can see that monitor. A monitor on another input or some docks may continue reporting an active link. The app cannot detect that reliably. Entries without vendor/model identity cannot authorize disabling, and newly created placeholders cannot replace the helper's protected external UUIDs. Virtual displays that present hardware identity may still count as externals.

Private ABI changes cannot be completely detected by symbol lookup. Verified online/offline status demonstrates a disconnect, not an electrical power measurement of the panel. The intended supported hardware is Apple Silicon MacBooks. macOS still controls physical closed-lid power behavior; ScreenOff clears its software disable and retains recovery responsibility until the lid is open and the panel is active.

## CLI

`--diagnose` is read-only and emits OS version, symbol availability, and topology JSON. `--recover` tells an existing instance to suspend automation and also invokes independent recovery. `--hardware-test` exercises the guarded menu transaction for two seconds and restores it. CLI modes do not change the saved automatic preference.
