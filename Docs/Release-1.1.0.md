ScreenOff 1.1.0 replaces the two display controls with one preference and adds an optional hidden menu bar icon.

- “Use built-in display” with an external monitor: on uses both displays; off automatically disables the built-in display and restores it when the external disconnects.
- The menu bar icon can be hidden or shown. Opening ScreenOff through Spotlight displays settings in the existing process, even with the icon hidden.
- Closing settings leaves the app running in the background. The power button quits and restores the built-in display.
- Existing preferences migrate automatically: the old automatic-off option being enabled corresponds to the new switch being off.
- The cable-removal recovery fix from 1.0.3 is preserved.

Validation: 295 automated policy, geometry and recovery checks; 11 native window and LaunchServices checks; four popover checks; and visual inspection. No new physical display test is claimed for this interface change. The user-confirmed unplug recovery in 1.0.3 remains the hardware evidence.

To update, quit the old ScreenOff with its power button, open **ScreenOff-1.1.0-arm64.dmg**, replace **ScreenOff.app** in **Applications**, and reopen it.

Assets include the DMG, app ZIP, source ZIP and SHA256SUMS.txt. Built for Apple Silicon and macOS 13+, ad-hoc signed without Apple notarization. If Gatekeeper blocks launch, attempt to open the app, then use **System Settings → Privacy & Security → Open Anyway**. Do not disable system security.
