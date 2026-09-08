ScreenOff 1.3.2 addresses a critical recovery failure after locking a Mac, closing its lid and unplugging the external monitor while the built-in display was disabled.

The previous helper could block inside a macOS display-configuration call and stop processing wake and recovery events. Logs from the affected Mac also showed excessive reconfiguration-wait messages in that single process.

- Locking immediately requests restoration, before the lid is closed.
- Each display change runs in a disposable child with a three-second timeout. The rescue supervisor stays responsive and retains the last verified built-in display ID.
- Sleep and lid closure can cancel an in-flight change. Recovery resumes after wake or lid opening, even if an AppKit wake notification is missed.
- A timed-out call waits for a real activity or topology transition before retrying. Repeated notifications cannot create an all-night retry loop.
- The main app and CLI no longer fall back to direct, unbounded configuration calls.

Validation: 271 automated checks, 15 native interface checks and GitHub CI pass. Physical open-lid checks passed for the installed app's supervised off/on path and independent recovery after heartbeat-channel closure. The real helper also passed three restore-only IPC checks. Simulated hardware covers the reported event sequence and eight-hour waiting/callback scenarios; real subprocess tests cover timeout, cancellation and restart. The exact physical sequence that previously required a forced reset has not yet been repeated with this version. A separate process-exit probe showed that macOS did not automatically undo the private disable; this release retains explicit independent recovery. Details and current physical validation are in Docs/Verification.md.

The single English switch, saved preference, absence of menu bar/Dock icons and existing README screenshot are preserved. The macOS private API remains a compatibility limitation; a bounded client process cannot guarantee recovery from a failure inside WindowServer, the kernel or display firmware.

To update, quit the old ScreenOff with its power button, replace ScreenOff.app in Applications using **ScreenOff-1.3.2-arm64.dmg**, and reopen it. Built for Apple Silicon and macOS 13+, ad-hoc signed without Apple notarization. If Gatekeeper blocks launch, attempt to open the app, then use **System Settings → Privacy & Security → Open Anyway**.
