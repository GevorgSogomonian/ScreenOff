ScreenOff 1.0.3 restores the built-in display when macOS stops enumerating it after cable removal.

Testing on the user's Mac identified the previous failure: the disabled built-in display disappeared even from the low-level list, while macOS created a virtual placeholder. Repeated enumeration could not find the panel to enable it.

- The app and independent recovery helper remember the last positively identified built-in display ID and use it only for emergency enabling.
- The macOS virtual placeholder is no longer counted as an external monitor.
- A newly discovered ID takes priority. The cached identifier is never used to disable a display.
- The two switches and corrected popover position are preserved.

Validation: 286 automated checks, including replay of the recorded display topology. After installing 1.0.3, all temporary diagnostic processes were stopped. The user disabled the built-in display, kept automatic mode enabled, removed the cable, and confirmed that the installed app now restored the built-in display. Details are in Docs/Verification.md.

To update, quit the old ScreenOff with its power button, open **ScreenOff-1.0.3-arm64.dmg**, replace **ScreenOff.app** in **Applications**, and reopen it. The automatic-mode preference is preserved.

Assets include the DMG, app ZIP, source ZIP and SHA256SUMS.txt. Built for Apple Silicon and macOS 13+, ad-hoc signed without Apple notarization. If Gatekeeper blocks launch, attempt to open the app, then use **System Settings → Privacy & Security → Open Anyway**.
