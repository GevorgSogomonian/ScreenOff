ScreenOff 1.0.2 improves recovery attempts when an external monitor is disconnected.

- A missing built-in display in macOS enumeration no longer cancels recovery.
- Sleep and a closed lid are no longer treated as successful restoration. The helper stays armed until the built-in display is confirmed active with the lid open.
- External-display removal events trigger recovery even when Core Graphics temporarily reports a stale active display.
- A recovery-helper failure, or startup with the built-in display already disabled, requests restoration.
- Recovery takes priority over automatic disabling. The two switches and corrected popover position are preserved.

Validation: 266 automated checks, three helper IPC/restore-only integration checks and four native popover checks. Physical cable-removal, sleep and lid scenarios had not yet been validated for this release. The later 1.0.3 release documents the remaining unplug failure and its confirmed fix.

To install, quit the old ScreenOff with its power button, open **ScreenOff-1.0.2-arm64.dmg**, replace **ScreenOff.app** in **Applications**, and reopen it. Your automatic-mode preference is preserved. After recovery, automatic disabling waits for the next external-monitor connection or an explicit switch action; further disabling remains blocked until restoration is confirmed.

Assets include the DMG, app ZIP, source ZIP and SHA256SUMS.txt. Built for Apple Silicon and macOS 13+, ad-hoc signed without Apple notarization. If Gatekeeper blocks launch, attempt to open the app, then use **System Settings → Privacy & Security → Open Anyway**. Do not disable system security.

ScreenOff uses a private macOS API. See Docs/Verification.md for validation details and limitations.
