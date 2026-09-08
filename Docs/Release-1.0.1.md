ScreenOff 1.0.1 fixes the settings popover's position below the menu bar icon.

The popover stays anchored to the status item when its content height changes. A display-configuration change closes an outdated popover; the next click positions it using the current screen geometry. The two switches and display-control behavior are unchanged.

Validation: 73 automated policy and geometry checks, plus four checks using a real AppKit popover. The gap below the icon was two points in all four scenarios.

To update, quit the old ScreenOff with its power button, open **ScreenOff-1.0.1-arm64.dmg**, replace **ScreenOff.app** in **Applications**, and reopen it. The automatic-mode preference is preserved. If macOS requires renewed login-item approval, the app displays instructions.

Assets include the DMG, app ZIP, source ZIP and SHA256SUMS.txt.

Built for Apple Silicon and macOS 13+. Ad-hoc signed, without Apple notarization. If Gatekeeper blocks launch, attempt to open the app, then use **System Settings → Privacy & Security → Open Anyway**. Do not disable system security.

ScreenOff uses a private macOS API; operating system updates may affect display disabling. Tests and hardware-validation limits are documented in Docs/Verification.md.
