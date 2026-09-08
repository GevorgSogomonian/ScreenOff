ScreenOff 1.2.0 removes the menu bar interface entirely.

The app now has one settings window with a single display preference, current status and a quit button. It has no menu bar or Dock icon. Open it through Spotlight or Applications in Finder; closing the window keeps display control running in the background. Reopening returns to the same process and window.

The icon visibility control and window minimization were removed. The saved display preference, login behavior, cable-removal recovery, automatic disabling after unlock and resource-use fixes are preserved.

Validation: all 330 policy/controller/recovery checks and 11 native interface checks passed. The removed popover's geometry tests are no longer applicable. No new physical cable or lock test is claimed for this interface change; earlier confirmed hardware results are recorded in Docs/Verification.md.

To update, quit the old version with its power button and replace **ScreenOff.app** in **Applications** using **ScreenOff-1.2.0-arm64.dmg**. Preferences are preserved.

Built for Apple Silicon and macOS 13+, ad-hoc signed without Apple notarization. If Gatekeeper blocks launch, attempt to open the app, then use **System Settings → Privacy & Security → Open Anyway**.
