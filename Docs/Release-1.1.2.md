ScreenOff 1.1.2 reapplies automatic display disabling after unlock or wake.

Previously, recovery during a lock or sleep cycle could leave automatic disabling paused until the external monitor reconnected, even with “Use built-in display” turned off.

- Observe Touch ID locking separately from system sleep, with a fallback through the existing poll and no additional timer.
- Reapply the saved preference after unlock, display wake or system wake, even if the cable has not changed. Wait for displays to settle and the previous recovery helper to finish.
- Never disable the only usable display. Selecting both displays keeps both enabled.
- Duplicate wake events do not repeatedly retry a failed attempt.
- Preserve the cable-removal recovery and overnight resource-use fixes.

Validation: 349 automated checks. The installed app also passed the physical Touch ID lock → external-monitor sleep → unlock scenario: the built-in display automatically disabled about two to three seconds after unlock. The user and a separate read-only observer confirmed the result. See Docs/Verification.md.

To update, quit the old version with its power button and replace **ScreenOff.app** in **Applications** using **ScreenOff-1.1.2-arm64.dmg**. Preferences are preserved.

Built for Apple Silicon and macOS 13+, ad-hoc signed without Apple notarization. If Gatekeeper blocks launch, attempt to open the app, then use **System Settings → Privacy & Security → Open Anyway**.
