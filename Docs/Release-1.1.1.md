ScreenOff 1.1.1 fixes excessive resource use with the lid closed, including when the Mac remains awake on mains power while the external monitor sleeps.

- Removed a recovery-command loop that could be triggered by callbacks from failed macOS commands.
- With the lid closed, the app and recovery helper each request restoration once, then wait for the lid to open. Recovery protection remains armed.
- With the lid open, repeated failed attempts are rate-limited. Lid opening and display-state changes are handled immediately.
- Removed unchanged state publications, redundant icon updates and window resizing. Waiting for lid opening no longer runs an animation.

In a reproducible two-second test with a simulated closed lid and macOS errors, the old version issued 20,004 commands and 60,012 UI updates; the new version issued one command and two updates. This measures the software loop, not battery consumption.

All 311 automated checks passed, including a simulated eight-hour closed-lid sequence, along with 11 window/Spotlight/LaunchServices checks and four popover-position checks. A full physical overnight test was not performed.

The update preserves the display preference and icon visibility. Built for Apple Silicon and macOS 13+, ad-hoc signed without Apple notarization.

To install, quit the old version with its power button and replace the app in Applications using the DMG.
