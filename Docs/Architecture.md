# Architecture

ScreenOff is a macOS accessory application. There is no Dock item, primary window, package dependency, network client, system extension, privileged service, or telemetry.

## Components

- `DisplayHardware`: dynamically resolves SkyLight symbols; enumerates online and software-disabled displays, reads lid state, performs nonpersistent display transactions, and exposes recovery.
- `DisplayPolicy`: pure state machine. Automatic mode and a temporary manual override determine desired built-in state. A changed external UUID set clears overrides. Built-in topology changes alone do not. A failure inhibits further automatic attempts until explicit user action or an external topology change.
- `DisplayController`: main-actor serialization, SwiftUI state, display callbacks plus a two-second polling fallback, sleep/wake handling, verified transactions, and login registration. It starts a rescue process before every disable and restores before releasing it.
- `RecoveryGuard`: launches the bundled helper using anonymous pipes. It requires a READY response before any off transaction, then sends a heartbeat once per second from the main run loop.
- `ScreenOffWatchdog`: a separate process with its own WindowServer connection and AppKit event loop. It checks every 750 ms and watches pipe input asynchronously; EOF, parent death, 8 seconds without a heartbeat, or no active external triggers recovery and exit. It only enables screens. No permanent launch agent is installed.
- `MenuView` / `AppDelegate`: two switches in a native popover, live status, quit button, single-instance handling.

## Display transaction

1. Enumerate all displays again, including offline entries, and resolve the built-in by the current `CGDisplayIsBuiltin` flag.
2. Before disabling, check open lid, active external, and absence of mirroring.
3. Begin configuration; dynamically call `SLSConfigureDisplayEnabled` (fallback `CGSConfigureDisplayEnabled`); cancel on configuration failure.
4. Commit `forAppOnly`. Do not change brightness, gamma, resolutions, mirror relationships, or the external display's enabled flag.
5. Poll the fresh topology for up to 1.8 seconds. Never report an off state from the function return code alone. If an external disappears mid-transaction, request recovery.
6. On error, inhibit repeat attempts and undo the operation. Keep the rescue helper available if verification of restoration fails.

The helper uses `forSession` when restoring so its enabled setting survives its own exit. Neither executable ever commits with `permanently`.

## Limitations

WindowServer's online/active state is evidence of a usable display link, not proof that a human can see that monitor. A monitor on another input or some docks may continue reporting an active link. The app cannot detect that reliably. Virtual displays reported active by macOS can also count as externals.

Private ABI changes cannot be completely detected by symbol lookup. Verified online/offline status demonstrates a disconnect, not an electrical power measurement of the panel. The intended supported hardware is Apple Silicon MacBooks. Closed-lid behavior is left to macOS.

## CLI

`--diagnose` is read-only and emits OS version, symbol availability, and topology JSON. `--recover` tells an existing instance to suspend automation and also invokes independent recovery. `--hardware-test` exercises the guarded menu transaction for two seconds and restores it. CLI modes do not change the saved automatic preference.
